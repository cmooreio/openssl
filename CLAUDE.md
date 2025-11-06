# CLAUDE.md

Instructions for Claude Code when working with this OpenSSL Docker image project.

## Quick Reference

**Build**: `make build` (native platform, fast) or `make build-multi` (all platforms, slow)
**Test**: `make test` or `docker compose up -d`
**Versions**: All in `versions.env`
**Base**: Alpine 3.22
**Registry**: cmooreio/openssl

## Key Commands

```bash
make build       # Build native (linux/arm64 or linux/amd64)
make build-multi # Build multi-platform (amd64 + arm64, slow)
make test        # Run tests
make scan        # Security scan
make version     # Show versions and detected platform
```

## Build Architecture

**Single-RUN Dockerfile** to minimize layers:
1. Install Alpine build tools + libs
2. Download & verify OpenSSL sources using `sha256sum -c`
3. Configure with `no-shared` for static linking
4. Compile with hardened flags, strip binaries
5. Create openssl user (UID 101, GID 101), cleanup

**Security**:
- Static OpenSSL linking (`no-shared`) for immutable crypto
- All sources verified via SHA256
- Compiler flags: `-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security`
- Linker flags: `-Wl,-z,relro -Wl,-z,now`
- Non-root user (101:101)
- SHA256 verification for all sources

## Version Management

**All versions in `versions.env`** - update there, then:
1. Run `make build`
2. Test with `make test`
3. Update README.md version section if needed

**Sources**:
- OpenSSL: https://www.openssl.org/source/

## Important Files

- **versions.env**: All versions and checksums (single source of truth)
- **Dockerfile**: Single-RUN build, Alpine 3.22 base
- **Makefile**: Auto-detects architecture, provides targets
- **build.sh**: Build script (used by Makefile)
- **docker-compose.yml**: Hardened production deployment
- **tests/**: smoke_test.sh, integration_test.sh, security_test.sh

## Critical Rules

### Security
- **Checksums**: Always `echo "$SHA256 file" | sha256sum -c -` (not grep)
- **OpenSSL**: Use `no-shared` for static linking
- **User**: openssl runs as UID 101, GID 101
- **tmpfs**: Must use `uid=101,gid=101` in docker-compose.yml

### Dockerfile Changes
- Keep single-RUN pattern (minimize layers)
- Verify all downloads have SHA256 checks
- Update `versions.env` ARG list if adding dependencies
- Test read-only filesystem: `docker run --read-only --tmpfs /tmp:uid=101,gid=101 ...`

### Build Performance
- **Native** (`make build`): 10-15 min, no emulation
- **Multi-platform** (`make build-multi`): 30-45 min with QEMU
- Use native for development, multi-platform for releases only

### Pushing Images

- **Atomic Multi-Tag Push**: `docker buildx build --push` with multiple `-t` flags pushes all tags atomically
- **Multiple tags pushed**: `latest`, `X.Y.Z` (version), and `X.Y` (major.minor)
- **Attestations**: Images include SBOM (`--sbom=true`) and provenance (`--provenance=true`) data
- **Verification**: Check with `docker buildx imagetools inspect cmooreio/openssl:<tag> --format '{{.Manifest.Digest}}'`
- All tags will have identical digests and attestations after push
- **Important**: Do not use `imagetools create` to re-tag after build, as it may interfere with attestations

### Common Tasks

- **Update OpenSSL**: Change `VERSION` and `SHA256` in `versions.env`, run `make build`
- **Test changes**: `make build && make test`
- **Check platforms**: `make version`
- **Push to registry**: `make push` (builds multi-platform and syncs all tags)
- **Security scan**: `make scan`
- **Generate SBOM**: `make sbom`

## Project Structure

```text
.
├── tests/                  # Test suite
│   ├── Makefile           # Test automation
│   ├── smoke_test.sh      # Basic functionality tests
│   ├── integration_test.sh # Full integration tests
│   └── security_test.sh   # Security-specific tests
├── Dockerfile              # Single-RUN hardened build
├── Makefile                # Build automation (auto-detects platform)
├── build.sh                # Secure build script (400 lines)
├── docker-compose.yml      # Production deployment config
├── versions.env            # Single source of truth for versions
├── CLAUDE.md               # This file - project instructions
├── README.md               # Comprehensive documentation
├── .editorconfig           # Editor consistency config
├── .dockerignore           # Docker build exclusions
├── .gitignore              # Git exclusions
├── .pre-commit-config.yaml # Pre-commit hooks config
├── .trivyignore            # Trivy scanner exclusions
└── renovate.json           # Renovate dependency automation

Note: SBOM files (sbom-*.json) are generated during build and not checked into git.
```

## Testing

The project has a comprehensive three-tier test suite:

### Smoke Tests (`tests/smoke_test.sh`)
- Binary exists and is executable
- Version check matches expected
- Basic OpenSSL commands work
- Non-root user validation
- Static linking verification

### Integration Tests (`tests/integration_test.sh`)
- RSA key generation
- Certificate generation
- Read-only filesystem compatibility
- Hash operations
- Encryption/decryption
- docker-compose integration

### Security Tests (`tests/security_test.sh`)
- Running as non-root user
- USER directive configured (Docker Scout requirement)
- No setuid/setgid binaries
- File permissions
- User shell restrictions
- Binary hardening (RELRO, BIND_NOW)
- OCI labels present

Run all tests: `make test`

## Configuration Files

### .editorconfig
Ensures consistent coding style across different editors:
- Unix-style newlines (lf)
- UTF-8 charset
- Shell scripts: 4-space indent
- Dockerfile/YAML/JSON: 2-space indent
- Makefile: tab indent

### .pre-commit-config.yaml
Pre-commit hooks for code quality:
- trailing-whitespace, end-of-file-fixer
- shellcheck (shell script linting)
- hadolint (Dockerfile linting)
- commitizen (commit message formatting)
- validate-versions (versions.env validation)
- no-secrets (secret detection)

### renovate.json
Dependency automation configuration:
- Scheduled updates (Monday before 5am)
- Security priority for OpenSSL updates
- Labels for different update types
- Dependency dashboard enabled

## Build Script Features (build.sh)

The build.sh script is a 300+ line secure build script with:

**Security Features**:
- No eval usage (security best practice)
- Input validation for SHA256, versions
- Interactive push confirmation
- Dry-run mode

**Validation Functions**:
- `validate_sha256()` - 64-char hex validation
- `validate_version()` - x.y.z format validation
- `load_versions()` - Loads and validates versions.env

**Build Configuration**:
- Multi-tag support (latest, version, major.minor)
- SBOM attestation with `--sbom=true`
- Provenance attestation with `--provenance=true`
- Platform auto-detection
- Vulnerability scanning integration
- Image signing with cosign

## Makefile Features

The Makefile provides comprehensive build automation with:

**Target Groups**:
1. **General**: help, all, check-deps
2. **Development**: validate, lint
3. **Building**: build, build-nc, build-single, build-multi, dry-run
4. **Testing**: test, smoke-test, integration-test
5. **Security**: scan, scan-all, sbom, sign, verify, verify-key
6. **Publishing**: push, push-signed
7. **Maintenance**: clean, clean-all, update-versions
8. **Documentation**: docs, version
9. **CI/CD**: ci, release, release-signed

**Platform Detection**:
- Auto-detects native architecture (arm64/amd64)
- Uses native platform by default for fast builds
- Multi-platform only for releases

## Docker Compose Features

The docker-compose.yml provides hardened production deployment:

**Security Hardening**:
- `read_only: true` - Read-only root filesystem
- `security_opt: no-new-privileges:true`
- `cap_drop: ALL` - Drops all capabilities
- tmpfs mounts with correct UID/GID (101:101)
- Resource limits (CPU: 1, Memory: 256M)
- Restart policy: "no" (CLI tool, not service)

## Common Development Workflows

### Making Changes to OpenSSL Version

1. Update `versions.env` with new VERSION and SHA256
2. Run `make validate` to check configuration
3. Run `make build` to build locally
4. Run `make test` to verify all tests pass
5. Update README.md if version changed
6. Run `make push` to publish (if authorized)

### Adding New Test

1. Edit appropriate test file in `tests/`
2. Make script executable: `chmod +x tests/your_test.sh`
3. Test locally: `./tests/your_test.sh`
4. Run full suite: `make test`

### Modifying Dockerfile

1. Edit Dockerfile
2. Run `make validate` to check syntax
3. Run `make lint` to check with hadolint
4. Run `make build` to test build
5. Run `make test` to verify functionality
6. Ensure single-RUN pattern is maintained

## Image Registry

- **Current**: cmooreio/openssl
- **Tags**: latest, X.Y.Z, X.Y
- **Platforms**: linux/amd64, linux/arm64

## Notes

- Static linking ensures OpenSSL crypto is immutable and not affected by system library updates
- Alpine 3.22 provides a minimal, secure base with regular security updates
- All security practices align with Docker Business Scout requirements
