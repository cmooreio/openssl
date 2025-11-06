# openssl

[![Docker Hub](https://img.shields.io/docker/v/cmooreio/openssl?sort=semver)](https://hub.docker.com/r/cmooreio/openssl)
[![Docker Image Size](https://img.shields.io/docker/image-size/cmooreio/openssl/latest)](https://hub.docker.com/r/cmooreio/openssl)
[![License](https://img.shields.io/github/license/cmooreio/openssl)](LICENSE)

Security-hardened OpenSSL running on Alpine Linux, built from source with static linking and compiler hardening.

## Features

- **Latest OpenSSL**: Built with OpenSSL 3.6.0
- **Security Hardened**: Static linking, runs as non-root, minimal attack surface
- **Multi-platform**: Supports amd64 and arm64 architectures
- **Production Ready**: Hardened build, verified sources, Docker Business compliant
- **Minimal Image**: Alpine-based with stripped binaries

## Quick Start

### Basic Usage

```bash
# Check OpenSSL version
docker run --rm cmooreio/openssl:latest version

# Generate RSA private key
docker run --rm cmooreio/openssl:latest genrsa -out /tmp/test.key 2048

# Hash data
echo "test data" | docker run --rm -i cmooreio/openssl:latest dgst -sha256
```

### Docker Compose

For persistent operations with mounted volumes:

```bash
docker compose up -d
```

The provided `docker-compose.yml` includes:
- Read-only root filesystem
- Dropped capabilities (principle of least privilege)
- Resource limits
- Proper tmpfs mounts for temporary operations

## Version Info

Current versions:
- **OpenSSL**: 3.6.0
- **Alpine Linux**: 3.22

```bash
$ docker run --rm cmooreio/openssl:latest version
OpenSSL 3.6.0 1 Oct 2025 (Library: OpenSSL 3.6.0 1 Oct 2025)
```

## Security

This image follows Docker Business security best practices:

### Build-Time Security
- ✅ **Compiler Hardening**: Stack protection, FORTIFY_SOURCE, RELRO
- ✅ **Static Linking**: OpenSSL statically linked (no-shared) for immutable crypto
- ✅ **Supply Chain Security**: Sources verified with SHA256 checksums
- ✅ **Minimal Attack Surface**: Build tools removed, debug symbols stripped

### Runtime Security
- ✅ **Non-Root Execution**: Runs as openssl:openssl (UID 101, GID 101)
- ✅ **Read-Only Filesystem**: Compatible with read-only root filesystem
- ✅ **Minimal Capabilities**: Drops all capabilities
- ✅ **Binary Hardening**: RELRO, BIND_NOW, stack canaries

### Supply Chain
- ✅ **SBOM Generation**: Software Bill of Materials in SPDX/CycloneDX formats
- ✅ **Image Signing**: Cosign signatures for verification
- ✅ **Provenance**: Build attestation included
- ✅ **Automated Scanning**: Trivy/Grype in CI pipeline
- ✅ **Dependency Updates**: Renovate automation

## For Developers

### Prerequisites

- Docker 20.10+ with Buildx
- Make
- Git
- (Optional) Trivy/Grype for scanning
- (Optional) Cosign for signing

### Quick Start

```bash
# Using Makefile (recommended)
make build       # Build for native architecture (fast, no emulation)
make build-multi # Build for all platforms (amd64, arm64) - slower
make test        # Run tests
make scan        # Security scan

# Or use build script directly
./build.sh
./build.sh --dry-run  # See command without executing
```

**Note**: The Makefile auto-detects your system architecture and builds natively by default to avoid slow QEMU emulation. Use `make build-multi` only when you need multi-platform images.

## Building

### Using Makefile (Recommended)

```bash
# Full pipeline
make all        # validate + build + test + scan

# Individual steps
make validate   # Validate configuration
make lint       # Lint Dockerfile and scripts
make build      # Build for native platform (linux/arm64 or linux/amd64)
make build-multi # Build for all platforms (requires QEMU emulation)
make test       # Run all tests
make scan       # Security scan
make push       # Build and push multi-platform to registry

# Architecture info
make version    # Show versions and detected platform

# See all targets
make help
```

**Platform Detection**: The Makefile automatically detects your system architecture:

- **Apple Silicon Mac**: Builds for `linux/arm64` natively (fast)
- **Intel Mac/x86 Linux**: Builds for `linux/amd64` natively (fast)
- **Multi-platform**: Use `make build-multi` or `make push` (slower, uses QEMU)

### Using build script

```bash
export VERSION=3.6.0
export SHA256=b6a5f44b7eb69e3fa35dbf15524405b44837a481d43d81daddde3ff21fcbb8e9

docker buildx build --no-cache --platform linux/amd64,linux/arm64 \
  --build-arg VERSION --build-arg SHA256 \
  -t cmooreio/openssl:latest \
  -t cmooreio/openssl:${VERSION} \
  -t cmooreio/openssl:3.6 \
  --sbom=true --provenance=true \
  --pull --push .
```

## Common Use Cases

### Certificate Operations

```bash
# Generate RSA private key
docker run --rm -v $(pwd):/certs cmooreio/openssl:latest \
  genrsa -out /certs/private.key 2048

# Generate self-signed certificate
docker run --rm -v $(pwd):/certs cmooreio/openssl:latest \
  req -new -x509 -key /certs/private.key -out /certs/cert.crt -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com"

# View certificate details
docker run --rm -v $(pwd):/certs cmooreio/openssl:latest \
  x509 -in /certs/cert.crt -text -noout
```

### Encryption/Decryption

```bash
# Encrypt file
docker run --rm -v $(pwd):/data cmooreio/openssl:latest \
  enc -aes-256-cbc -salt -in /data/plaintext.txt -out /data/encrypted.bin

# Decrypt file
docker run --rm -v $(pwd):/data cmooreio/openssl:latest \
  enc -aes-256-cbc -d -in /data/encrypted.bin -out /data/decrypted.txt
```

### Hash Operations

```bash
# SHA256 hash
echo "test data" | docker run --rm -i cmooreio/openssl:latest dgst -sha256

# File hash
docker run --rm -v $(pwd):/data cmooreio/openssl:latest \
  dgst -sha256 /data/file.txt
```

## Testing

```bash
# Run all tests
make test

# Individual test suites
make smoke-test        # Basic functionality
make integration-test  # Full integration tests
make -C tests security # Security-specific tests
```

## Building & Publishing

This project uses manual build and publish workflows.

### Quick Build

Build for your native architecture:
```bash
make build  # Fast native build (10-15 min)
```

### Multi-Platform Build

Build for both amd64 and arm64:
```bash
make build-multi  # Multi-platform build (30-45 min, uses QEMU)
```

### Publishing Images

Build and push to your container registry:
```bash
# Configure your registry in Makefile (IMAGE_REPO variable)
make push         # Build and push multi-platform
make push-signed  # Build, push, and sign with Cosign
```

### Available Images

**Docker Hub**: `cmooreio/openssl:latest`

### Security Tools

Optional security scanning and SBOM generation:
```bash
make scan  # Vulnerability scan with Trivy
make sbom  # Generate Software Bill of Materials (SPDX and CycloneDX formats)
```

**Note**: SBOM files are automatically generated during multi-platform builds with `--sbom=true` attestations. To generate them manually after building, use `make sbom` which requires [syft](https://github.com/anchore/syft) to be installed.

## Tags

- `latest` - Latest stable OpenSSL version (3.6.0)
- `3.6.0` - Specific OpenSSL version
- `3.6` - Major.minor version (tracks latest patch)

## Deployment Best Practices

### Production Configuration

1. **Use Docker Compose**: See `docker-compose.yml` for hardened configuration
2. **Resource Limits**: Set appropriate CPU and memory limits
3. **Read-only Filesystem**: Mount root filesystem as read-only
4. **Least Privilege**: Drop all unnecessary Linux capabilities
5. **Volume Mounting**: Mount directories for certificate/key operations

### Example with Mounted Volumes

```yaml
services:
  openssl:
    image: cmooreio/openssl:latest
    volumes:
      - ./certs:/certs:rw
      - ./private:/private:ro
    read_only: true
    tmpfs:
      - /tmp:uid=101,gid=101
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

## Project Structure

```text
.
├── tests/                  # Test suite
│   ├── Makefile
│   ├── smoke_test.sh
│   ├── integration_test.sh
│   └── security_test.sh
├── Dockerfile              # Hardened image build
├── Makefile                # Build automation
├── build.sh                # Secure build script
├── docker-compose.yml      # Production deployment
├── versions.env            # Centralized versions
├── CLAUDE.md               # Project instructions
├── .editorconfig           # Editor consistency
├── .dockerignore           # Docker build exclusions
├── .gitignore              # Git exclusions
├── .pre-commit-config.yaml # Pre-commit hooks
└── renovate.json           # Dependency automation
```

## Version Management

All versions are managed in `versions.env`. To update OpenSSL:

1. Edit `versions.env` with new VERSION and SHA256
2. Run `make validate` to verify configuration
3. Run `make build` to build the new version
4. Run `make test` to verify functionality
5. Run `make push` to publish (if authorized)

## License

[MIT License](LICENSE)

## Support

- **Issues**: [GitHub Issues](https://github.com/cmooreio/openssl/issues)
- **Docker Hub**: [cmooreio/openssl](https://hub.docker.com/r/cmooreio/openssl)
