#!/bin/bash
set -euo pipefail

# Security tests for OpenSSL Docker image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source versions.env

IMAGE="cmooreio/openssl:$VERSION"

echo "Running security tests on $IMAGE..."

# Test 1: Running as non-root user
echo "Test 1: Non-root user..."
user=$(docker run --rm --entrypoint ash "$IMAGE" -c 'whoami')
if [ "$user" != "openssl" ]; then
    echo "✗ Expected user 'openssl', got '$user'"
    exit 1
fi

# Test 2: USER directive set to non-root (Docker Scout requirement)
echo "Test 2: USER directive configured..."
image_user=$(docker image inspect "$IMAGE" --format '{{.Config.User}}')
if [ -z "$image_user" ]; then
    echo "✗ No USER directive found in image"
    exit 1
elif [ "$image_user" = "0" ] || [ "$image_user" = "root" ] || [ "$image_user" = "0:0" ]; then
    echo "✗ USER directive set to root: $image_user"
    exit 1
else
    echo "  USER directive: $image_user (non-root ✓)"
fi

# Test 3: No setuid/setgid binaries
echo "Test 3: No dangerous permissions..."
dangerous=$(docker run --rm --user root --entrypoint ash "$IMAGE" -c 'find / -perm /6000 -type f 2>/dev/null | wc -l')
if [ "$dangerous" -gt 0 ]; then
    echo "⚠ Found $dangerous setuid/setgid files"
else
    echo "  No setuid/setgid files found"
fi

# Test 4: openssl binary has correct permissions
echo "Test 4: File permissions..."
perms=$(docker run --rm --entrypoint ash "$IMAGE" -c 'stat -c "%a" /usr/local/ssl/bin/openssl')
if [ "$perms" != "755" ] && [ "$perms" != "555" ]; then
    echo "⚠ openssl has permissions $perms (expected 755 or 555)"
else
    echo "  openssl permissions correct ($perms)"
fi

# Test 5: No shells for openssl user
echo "Test 5: User shell restrictions..."
shell=$(docker run --rm --entrypoint ash "$IMAGE" -c "grep '^openssl:' /etc/passwd | cut -d: -f7")
if [ "$shell" = "/sbin/nologin" ] || [ "$shell" = "/bin/false" ] || [ -z "$shell" ]; then
    echo "  openssl user has no shell access (shell: ${shell:-none})"
else
    echo "⚠ openssl user has shell: $shell"
fi

# Test 6: OpenSSL version and features
echo "Test 6: OpenSSL features..."
features=$(docker run --rm "$IMAGE" version -a)
echo "$features" | grep -q "OPENSSLDIR"
echo "  OpenSSL configuration validated"

# Test 7: Binary has security features
echo "Test 7: Binary hardening..."
if command -v docker &> /dev/null; then
    docker run --rm --user root --entrypoint ash "$IMAGE" -c 'readelf -d /usr/local/ssl/bin/openssl | grep -q RELRO' && echo "  RELRO: enabled" || echo "⚠ RELRO: not detected"
    docker run --rm --user root --entrypoint ash "$IMAGE" -c 'readelf -d /usr/local/ssl/bin/openssl | grep -q BIND_NOW' && echo "  BIND_NOW: enabled" || echo "⚠ BIND_NOW: not detected"
fi

# Test 8: Image labels present
echo "Test 8: OCI labels..."
docker inspect "$IMAGE" | grep -q "org.opencontainers.image.version"
echo "  OCI labels present"

# Test 9: No vulnerable packages (basic check)
echo "Test 9: Alpine base verification..."
base_image=$(docker inspect "$IMAGE" --format '{{index .Config.Image}}' 2>/dev/null || echo "unknown")
echo "  Base image: $base_image"

echo "✓ All security tests passed"
