# https://hub.docker.com/orgs/cmooreio/hardened-images/catalog/dhi/alpine-base/images
FROM cmooreio/dhi-alpine-base:3.22

# https://www.openssl.org/source/
ARG VERSION SHA256 BUILD_DATE VCS_REF

LABEL org.opencontainers.image.title="openssl" \
      org.opencontainers.image.description="Security-hardened OpenSSL built from source on Alpine Linux" \
      org.opencontainers.image.vendor="cmooreio" \
      org.opencontainers.image.source="https://github.com/cmooreio/openssl" \
      org.opencontainers.image.url="https://github.com/cmooreio/openssl" \
      org.opencontainers.image.documentation="https://github.com/cmooreio/openssl/blob/master/README.md" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.authors="cmooreio" \
      io.cmooreio.openssl.version="${VERSION}"

# Security: Set compiler hardening flags
ENV CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security" \
    CXXFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security" \
    LDFLAGS="-Wl,-z,relro -Wl,-z,now"

# Set shell options for better error handling (Alpine uses ash)
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

# Set working directory for build
WORKDIR /usr/local/src

# hadolint ignore=DL3003,DL3018
RUN : \
  && apk update \
  && apk upgrade \
  && apk add --no-cache \
      alpine-sdk \
      curl \
      linux-headers \
      perl \
      wget \
  && curl -L https://github.com/openssl/openssl/releases/download/openssl-${VERSION}/openssl-${VERSION}.tar.gz -o openssl-${VERSION}.tar.gz \
  && echo "${SHA256}  openssl-${VERSION}.tar.gz" | sha256sum -c - \
  && tar -xf openssl-${VERSION}.tar.gz \
  && cd /usr/local/src/openssl-${VERSION} \
  && ./config \
    --prefix=/usr/local/ssl \
    --openssldir=/usr/local/ssl \
    no-shared \
    threads \
  && make -j"$(nproc)" \
  && make install \
  && strip /usr/local/ssl/bin/openssl \
  && apk del --no-network \
      alpine-sdk \
      curl \
      linux-headers \
  && cd / \
  && rm -rf /var/cache/apk/* \
  && rm -f /usr/local/src/*.tar.gz \
  && rm -rf /usr/local/src/* \
  && rm -rf /tmp/* \
  && rm -rf /root/.cache \
  && addgroup -g 101 -S openssl \
  && adduser -D -u 101 -S -G openssl -s /sbin/nologin openssl

# Set environment for OpenSSL
ENV PATH=/usr/local/ssl/bin:$PATH \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

WORKDIR /

# Run as non-root user (UID:GID 101:101)
USER 101:101

ENTRYPOINT ["openssl"]
