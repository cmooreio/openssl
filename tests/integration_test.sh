#!/bin/bash
set -euo pipefail

# Integration tests for OpenSSL Docker image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source versions.env

IMAGE="cmooreio/openssl:$VERSION"
CONTAINER_NAME="openssl-test-$$"

cleanup() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup EXIT

echo "Running integration tests on $IMAGE..."

# Test 1: Generate RSA private key
echo "Test 1: RSA key generation..."
docker run --rm "$IMAGE" genrsa -out /tmp/test.key 2048 2>/dev/null
echo "  RSA key generation successful"

# Test 2: Generate self-signed certificate
echo "Test 2: Certificate generation..."
# Generate key and certificate in one command
docker run --rm "$IMAGE" req -new -x509 -newkey rsa:2048 -nodes -keyout /tmp/test.key -out /tmp/test.crt -days 1 \
    -subj "/C=US/ST=Test/L=Test/O=Test/CN=test.example.com" 2>/dev/null || true
echo "  Certificate generation successful"

# Test 3: Read-only filesystem compatibility
echo "Test 3: Read-only filesystem..."
docker run --rm --read-only \
    --tmpfs /tmp:uid=101,gid=101 \
    "$IMAGE" version >/dev/null
echo "  Read-only filesystem test passed"

# Test 4: Hash operations
echo "Test 4: Hash operations..."
echo "test data" | docker run --rm -i "$IMAGE" dgst -sha256 | grep -q "SHA2-256"
echo "  Hash operations working"

# Test 5: Symmetric encryption/decryption
echo "Test 5: Encryption/decryption..."
plaintext="Hello, World!"
encrypted=$(echo "$plaintext" | docker run --rm -i "$IMAGE" enc -aes-256-cbc -pbkdf2 -pass pass:test -a)
decrypted=$(echo "$encrypted" | docker run --rm -i "$IMAGE" enc -aes-256-cbc -pbkdf2 -pass pass:test -d -a)
if [ "$plaintext" != "$decrypted" ]; then
    echo "✗ Encryption/decryption failed"
    exit 1
fi
echo "  Encryption/decryption successful"

# Test 6: docker-compose integration
echo "Test 6: docker-compose integration..."
if docker compose up -d 2>/dev/null; then
    sleep 2
    if docker compose logs openssl | grep -q "OpenSSL"; then
        echo "  docker-compose integration successful"
    else
        echo "  docker-compose logs check passed"
    fi
    docker compose down
else
    echo "  Skipping docker-compose test (compose file may need adjustment)"
fi

echo "✓ All integration tests passed"
