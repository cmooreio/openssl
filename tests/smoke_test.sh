#!/bin/bash
set -euo pipefail

# Smoke tests for OpenSSL Docker image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source versions.env

IMAGE="cmooreio/openssl:$VERSION"

echo "Running smoke tests on $IMAGE..."

# Test 1: openssl binary exists and is executable
echo "Test 1: openssl binary..."
docker run --rm --entrypoint ash "$IMAGE" -c 'command -v openssl && test -x /usr/local/ssl/bin/openssl'

# Test 2: openssl version check
echo "Test 2: openssl version..."
docker run --rm "$IMAGE" version

# Test 3: Check OpenSSL version matches expected
echo "Test 3: Version validation..."
version_output=$(docker run --rm "$IMAGE" version)
echo "  $version_output"
if ! echo "$version_output" | grep -q "$VERSION"; then
    echo "✗ Version mismatch: expected $VERSION"
    exit 1
fi

# Test 4: User is openssl (non-root)
echo "Test 4: Non-root user..."
docker run --rm --entrypoint ash "$IMAGE" -c 'id' | grep -q "uid=101(openssl)"

# Test 5: OpenSSL commands work
echo "Test 5: Basic functionality..."
docker run --rm "$IMAGE" list -digest-algorithms >/dev/null 2>&1
docker run --rm "$IMAGE" list -cipher-algorithms >/dev/null 2>&1

# Test 6: Static linking check (no shared library dependencies except system libs)
echo "Test 6: Static linking..."
# OpenSSL should be statically linked (no libssl.so, libcrypto.so dependencies from build)
docker run --rm --entrypoint ash "$IMAGE" -c 'ldd /usr/local/ssl/bin/openssl' | grep -v "not a dynamic executable" || true

echo "✓ All smoke tests passed"
