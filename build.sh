#!/bin/bash
set -euo pipefail

# Secure build script for OpenSSL Docker image
# - Removes eval usage to prevent command injection
# - Adds input validation
# - Supports SBOM generation and image signing
# - Provides dry-run mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Detect native architecture for default platform
UNAME_M=$(uname -m)
case "$UNAME_M" in
    x86_64)
        NATIVE_PLATFORM="linux/amd64"
        ;;
    aarch64|arm64)
        NATIVE_PLATFORM="linux/arm64"
        ;;
    *)
        NATIVE_PLATFORM="linux/amd64"
        ;;
esac

# Default options
# Default to native platform to avoid slow QEMU emulation
# Use --platform flag or PLATFORMS env var to override
PLATFORMS="${PLATFORMS:-$NATIVE_PLATFORM}"
PUSH="${PUSH:-false}"
NO_CACHE="${NO_CACHE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SIGN_IMAGE="${SIGN_IMAGE:-false}"
GENERATE_SBOM="${GENERATE_SBOM:-true}"
SCAN_IMAGE="${SCAN_IMAGE:-true}"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Validation functions
validate_sha256() {
    local sha="$1"
    if [[ ! "$sha" =~ ^[a-f0-9]{64}$ ]]; then
        log_error "Invalid SHA256 checksum: $sha"
        return 1
    fi
}

validate_version() {
    local version="$1"
    # Allow x.y.z or x.y.z.w format (for OpenSSL)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([a-z])?$ ]]; then
        log_error "Invalid version format: $version (expected x.y.z or x.y.za)"
        return 1
    fi
}

# Load and validate versions.env
load_versions() {
    if [[ ! -f "versions.env" ]]; then
        log_error "versions.env not found"
        exit 1
    fi

    log_info "Loading versions from versions.env..."
    # shellcheck source=/dev/null
    source versions.env

    # Validate required variables
    local required_vars=(
        VERSION SHA256
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "$var is not set in versions.env"
            exit 1
        fi
    done

    # Validate formats
    # shellcheck disable=SC2153
    validate_version "$VERSION" || exit 1
    validate_sha256 "$SHA256" || exit 1

    # Set build metadata
    BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    export BUILD_DATE VCS_REF
}

# Display build configuration
display_config() {
    log_info "Build Configuration:"
    echo "  OpenSSL:      $VERSION"
    echo "  Platforms:    $PLATFORMS"
    echo "  Push:         $PUSH"
    echo "  Sign:         $SIGN_IMAGE"
    echo "  SBOM:         $GENERATE_SBOM"
    echo "  Scan:         $SCAN_IMAGE"
    echo "  Build Date:   $BUILD_DATE"
    echo "  VCS Ref:      $VCS_REF"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --push)
                PUSH=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --platform)
                PLATFORMS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --sign)
                SIGN_IMAGE=true
                shift
                ;;
            --no-sbom)
                GENERATE_SBOM=false
                shift
                ;;
            --no-scan)
                SCAN_IMAGE=false
                shift
                ;;
            --help)
                cat <<EOF
Usage: $0 [OPTIONS]

Secure build script for OpenSSL Docker images with supply chain security features.

Options:
  --push          Push images to registry after build
  --no-cache      Build without using cache
  --platform      Specify platforms (default: $NATIVE_PLATFORM)
  --dry-run       Show build command without executing
  --sign          Sign image with cosign (requires cosign installed)
  --no-sbom       Skip SBOM generation
  --no-scan       Skip vulnerability scanning
  --help          Show this help message

Environment variables:
  PUSH=true       Same as --push
  NO_CACHE=true   Same as --no-cache
  PLATFORMS=...   Same as --platform
  DRY_RUN=true    Same as --dry-run
  SIGN_IMAGE=true Same as --sign
  DEBUG=true      Enable debug logging

Examples:
  # Build locally
  $0

  # Build and push to registry
  $0 --push

  # Build for single platform with no cache
  $0 --platform linux/amd64 --no-cache

  # Dry run to see build command
  $0 --dry-run

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Build Docker image
build_image() {
    local -a build_args=(
        "buildx" "build"
    )

    # Add cache option
    if [[ "$NO_CACHE" == "true" ]]; then
        build_args+=("--no-cache")
    fi

    # Add platform
    build_args+=("--platform" "$PLATFORMS")

    # Add build arguments - NO eval, direct array construction
    build_args+=(
        "--build-arg" "VERSION=$VERSION"
        "--build-arg" "SHA256=$SHA256"
        "--build-arg" "BUILD_DATE=$BUILD_DATE"
        "--build-arg" "VCS_REF=$VCS_REF"
    )

    # Determine version tags
    local MAJOR_MINOR
    MAJOR_MINOR=$(echo "$VERSION" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')

    # Add tags
    build_args+=(
        "-t" "cmooreio/openssl:latest"
        "-t" "cmooreio/openssl:$VERSION"
        "-t" "cmooreio/openssl:$MAJOR_MINOR"
    )

    # Add SBOM attestation
    if [[ "$GENERATE_SBOM" == "true" ]]; then
        build_args+=("--sbom=true")
    fi

    # Add provenance attestation
    build_args+=("--provenance=true")

    # Add push/load option
    if [[ "$PUSH" == "true" ]]; then
        build_args+=("--push")
    else
        build_args+=("--load")
    fi

    # Add pull flag
    build_args+=("--pull")

    # Add context
    build_args+=(".")

    # Display command
    log_info "Build command:"
    echo "docker ${build_args[*]}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - not executing build"
        return 0
    fi

    # Confirm before pushing
    if [[ "$PUSH" == "true" ]]; then
        read -p "This will build and push images to Docker Hub. Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warn "Aborted by user"
            exit 0
        fi
    fi

    # Execute build - NO EVAL, direct command execution
    log_info "Starting build..."
    if docker "${build_args[@]}"; then
        log_info "✓ Build completed successfully"
        return 0
    else
        log_error "✗ Build failed"
        return 1
    fi
}

# Scan image for vulnerabilities
scan_image() {
    if [[ "$SCAN_IMAGE" != "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log_info "Scanning image for vulnerabilities..."

    if command -v trivy &> /dev/null; then
        trivy image --severity HIGH,CRITICAL "cmooreio/openssl:$VERSION" || log_warn "Trivy scan found issues"
    elif command -v grype &> /dev/null; then
        grype "cmooreio/openssl:$VERSION" || log_warn "Grype scan found issues"
    else
        log_warn "No vulnerability scanner found (install trivy or grype)"
    fi
}

# Sign image with cosign
sign_image() {
    if [[ "$SIGN_IMAGE" != "true" ]] || [[ "$PUSH" != "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    if ! command -v cosign &> /dev/null; then
        log_warn "cosign not found - skipping image signing"
        return 0
    fi

    log_info "Signing image with cosign..."
    cosign sign "cmooreio/openssl:$VERSION" || log_error "Failed to sign image"
}

# Display success message
display_success() {
    local MAJOR_MINOR
    MAJOR_MINOR=$(echo "$VERSION" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')

    echo ""
    log_info "✓ All operations completed successfully"
    echo ""
    echo "Tags created:"
    echo "  - cmooreio/openssl:latest"
    echo "  - cmooreio/openssl:$VERSION"
    echo "  - cmooreio/openssl:$MAJOR_MINOR"

    if [[ "$PUSH" != "true" ]]; then
        echo ""
        echo "To test locally:"
        echo "  docker run --rm cmooreio/openssl:latest version"
        echo "  docker compose up -d"
    fi

    if [[ "$SIGN_IMAGE" == "true" ]] && [[ "$PUSH" == "true" ]]; then
        echo ""
        echo "Image signed with cosign. Verify with:"
        echo "  cosign verify cmooreio/openssl:$VERSION"
    fi
}

# Main execution
main() {
    parse_args "$@"
    load_versions
    display_config

    if ! build_image; then
        exit 1
    fi

    scan_image
    sign_image
    display_success
}

main "$@"
