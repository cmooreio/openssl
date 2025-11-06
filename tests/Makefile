.PHONY: all test smoke integration security clean

IMAGE_NAME := cmooreio/openssl
IMAGE_TAG := $(shell source ../versions.env && echo $$VERSION)

all: test

test: smoke integration security

smoke:
	@echo "Running smoke tests..."
	@./smoke_test.sh

integration:
	@echo "Running integration tests..."
	@./integration_test.sh

security:
	@echo "Running security tests..."
	@./security_test.sh

clean:
	@docker compose down -v 2>/dev/null || true
	@docker rm -f openssl-test 2>/dev/null || true
