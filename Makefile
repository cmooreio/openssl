.PHONY: help build build-nc push test scan sign sbom clean lint validate check-deps all

# Load versions from versions.env
include versions.env

# Image configuration
IMAGE_REPO := cmooreio/openssl
IMAGE_TAG := $(VERSION)
IMAGE_NAME := $(IMAGE_REPO):$(IMAGE_TAG)
IMAGE_LATEST := $(IMAGE_REPO):latest

# Detect native architecture
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
	NATIVE_ARCH := amd64
else ifeq ($(UNAME_M),aarch64)
	NATIVE_ARCH := arm64
else ifeq ($(UNAME_M),arm64)
	NATIVE_ARCH := arm64
else
	NATIVE_ARCH := amd64
endif
NATIVE_PLATFORM := linux/$(NATIVE_ARCH)

# Build configuration
# For local builds: use native platform only (faster, no emulation)
# For CI/CD builds (push): use multi-platform
PLATFORMS := $(NATIVE_PLATFORM)
MULTI_PLATFORMS := linux/amd64,linux/arm64
BUILD_ARGS := --build-arg VERSION=$(VERSION) \
              --build-arg SHA256=$(SHA256)

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
NC     := \033[0m # No Color

##@ General

help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

all: validate build test scan ## Run full build pipeline (validate, build, test, scan)

check-deps: ## Check for required dependencies
	@echo "$(GREEN)Checking dependencies...$(NC)"
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)docker is required but not installed$(NC)"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "$(RED)git is required but not installed$(NC)"; exit 1; }
	@docker buildx version >/dev/null 2>&1 || { echo "$(RED)docker buildx is required$(NC)"; exit 1; }
	@echo "$(GREEN)✓ All required dependencies found$(NC)"

##@ Development

validate: ## Validate configuration files and versions
	@echo "$(GREEN)Validating configuration...$(NC)"
	@test -f versions.env || { echo "$(RED)versions.env not found$(NC)"; exit 1; }
	@test -f Dockerfile || { echo "$(RED)Dockerfile not found$(NC)"; exit 1; }
	@grep -q "VERSION=" versions.env || { echo "$(RED)VERSION not set in versions.env$(NC)"; exit 1; }
	@echo "$(GREEN)✓ Configuration validated$(NC)"

lint: ## Lint Dockerfile and shell scripts
	@echo "$(GREEN)Linting files...$(NC)"
	@if command -v hadolint >/dev/null 2>&1; then \
		hadolint Dockerfile || echo "$(YELLOW)⚠ Hadolint found issues$(NC)"; \
	else \
		echo "$(YELLOW)hadolint not installed, skipping Dockerfile linting$(NC)"; \
	fi
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck build.sh || echo "$(YELLOW)⚠ shellcheck found issues$(NC)"; \
	else \
		echo "$(YELLOW)shellcheck not installed, skipping script linting$(NC)"; \
	fi
	@echo "$(GREEN)✓ Linting complete$(NC)"

##@ Building

build: check-deps validate ## Build Docker image locally
	@echo "$(GREEN)Building image...$(NC)"
	@./build.sh

build-nc: check-deps validate ## Build Docker image without cache
	@echo "$(GREEN)Building image without cache...$(NC)"
	@./build.sh --no-cache

build-single: check-deps validate ## Build for native platform only ($(NATIVE_PLATFORM))
	@echo "$(GREEN)Building for $(NATIVE_PLATFORM)...$(NC)"
	@./build.sh --platform $(NATIVE_PLATFORM)

build-multi: check-deps validate ## Build for all platforms (amd64, arm64) - requires emulation
	@echo "$(YELLOW)Warning: Multi-platform build uses emulation and may be slow$(NC)"
	@echo "$(GREEN)Building for $(MULTI_PLATFORMS)...$(NC)"
	@PLATFORMS=$(MULTI_PLATFORMS) ./build.sh

dry-run: ## Show build command without executing
	@./build.sh --dry-run

##@ Testing

test: ## Run container tests
	@echo "$(GREEN)Testing container...$(NC)"
	@if [ -d tests ]; then \
		$(MAKE) -C tests all; \
	else \
		echo "$(YELLOW)No tests directory found, running basic smoke test$(NC)"; \
		$(MAKE) smoke-test; \
	fi

smoke-test: ## Run basic smoke test on built image
	@echo "$(GREEN)Running smoke test...$(NC)"
	@docker run --rm $(IMAGE_NAME) version
	@echo "$(GREEN)✓ Smoke test passed$(NC)"

integration-test: ## Run integration tests with docker-compose
	@echo "$(GREEN)Running integration tests...$(NC)"
	@docker compose up -d
	@sleep 5
	@docker compose exec openssl version || { docker compose down; exit 1; }
	@docker compose down
	@echo "$(GREEN)✓ Integration test passed$(NC)"

##@ Security

scan: ## Scan image for vulnerabilities
	@echo "$(GREEN)Scanning for vulnerabilities...$(NC)"
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image --severity HIGH,CRITICAL $(IMAGE_NAME); \
	elif command -v grype >/dev/null 2>&1; then \
		grype $(IMAGE_NAME); \
	else \
		echo "$(YELLOW)No scanner found (install trivy or grype)$(NC)"; \
	fi

scan-all: ## Scan for all vulnerability levels
	@echo "$(GREEN)Scanning for all vulnerabilities...$(NC)"
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image $(IMAGE_NAME); \
	else \
		echo "$(YELLOW)trivy not installed$(NC)"; \
	fi

sbom: ## Generate SBOM (Software Bill of Materials)
	@echo "$(GREEN)Generating SBOM...$(NC)"
	@if command -v syft >/dev/null 2>&1; then \
		syft $(IMAGE_NAME) -o spdx-json > sbom-spdx.json; \
		syft $(IMAGE_NAME) -o cyclonedx-json > sbom-cyclonedx.json; \
		echo "$(GREEN)✓ SBOM generated: sbom-spdx.json, sbom-cyclonedx.json$(NC)"; \
	else \
		echo "$(YELLOW)syft not installed, skipping SBOM generation$(NC)"; \
	fi

sign: ## Sign image with cosign
	@echo "$(GREEN)Signing image...$(NC)"
	@if command -v cosign >/dev/null 2>&1; then \
		cosign sign $(IMAGE_NAME); \
		echo "$(GREEN)✓ Image signed$(NC)"; \
	else \
		echo "$(YELLOW)cosign not installed$(NC)"; \
	fi

verify: ## Verify image signature (keyless)
	@if command -v cosign >/dev/null 2>&1; then \
		echo "$(GREEN)Verifying image signature (keyless)...$(NC)"; \
		cosign verify $(IMAGE_NAME) \
			--certificate-identity-regexp=".*" \
			--certificate-oidc-issuer-regexp=".*"; \
	else \
		echo "$(YELLOW)cosign not installed$(NC)"; \
	fi

verify-key: ## Verify image signature with public key
	@if command -v cosign >/dev/null 2>&1; then \
		if [ -f cosign.pub ]; then \
			echo "$(GREEN)Verifying image signature with key...$(NC)"; \
			cosign verify --key cosign.pub $(IMAGE_NAME); \
		else \
			echo "$(YELLOW)cosign.pub not found$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)cosign not installed$(NC)"; \
	fi

##@ Publishing

push: check-deps ## Build and push multi-platform images to registry
	@echo "$(GREEN)Building and pushing multi-platform images ($(MULTI_PLATFORMS))...$(NC)"
	@PLATFORMS=$(MULTI_PLATFORMS) ./build.sh --push

push-signed: check-deps ## Build, push, and sign multi-platform images
	@echo "$(GREEN)Building, pushing, and signing multi-platform images...$(NC)"
	@PLATFORMS=$(MULTI_PLATFORMS) ./build.sh --push --sign

##@ Maintenance

clean: ## Clean up local images and build cache
	@echo "$(GREEN)Cleaning up...$(NC)"
	@docker rmi $(IMAGE_NAME) $(IMAGE_LATEST) 2>/dev/null || true
	@docker builder prune -f
	@rm -f sbom-*.json
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

clean-all: clean ## Clean everything including dangling images
	@echo "$(GREEN)Deep cleaning...$(NC)"
	@docker system prune -af
	@echo "$(GREEN)✓ Deep cleanup complete$(NC)"

update-versions: ## Interactive helper to update version numbers
	@echo "$(YELLOW)Update versions.env manually, then run 'make validate'$(NC)"
	@echo "Current versions:"
	@grep "VERSION=" versions.env | grep -v "^#"

##@ Documentation

docs: ## Generate documentation
	@echo "$(GREEN)Documentation is in README.md and CLAUDE.md$(NC)"

version: ## Show current version information
	@echo "OpenSSL:      $(VERSION)"
	@echo "Image:        $(IMAGE_NAME)"
	@echo "Native:       $(NATIVE_PLATFORM)"
	@echo "Multi:        $(MULTI_PLATFORMS)"

##@ CI/CD

ci: validate lint build test scan ## Run CI pipeline
	@echo "$(GREEN)✓ CI pipeline completed$(NC)"

release: validate lint build test scan push ## Run full release pipeline
	@echo "$(GREEN)✓ Release pipeline completed$(NC)"

release-signed: validate lint build test scan push-signed ## Full release with signing
	@echo "$(GREEN)✓ Signed release completed$(NC)"
