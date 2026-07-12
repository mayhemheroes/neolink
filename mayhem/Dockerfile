# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — RUST target (cargo / cargo-fuzz). Builds ON TOP of the
# org C/C++ base (ghcr.io/mayhemheroes/base), adding a pinned Rust toolchain +
# cargo-fuzz under /opt/toolchains/rust, then runs the per-repo mayhem/build.sh.
#
# neolink is a Rust workspace; the fuzzed code is the neolink_core crate
# (crates/core), driven by the additive cargo-fuzz crate at mayhem/fuzz.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] -t neolink-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted (no '=') so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# Rust toolchain pinned by date (nightly needed for -Zsanitizer=address) + pinned cargo-fuzz.
ARG RUST_CHANNEL=nightly-2025-09-05
ARG CARGO_FUZZ_VERSION=0.12.0

# Fixed, $HOME-independent prefix: the cargo registry this first (online) build
# populates is found again by the PATCH tier's offline re-run of build.sh.
ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
RUN set -eux; \
    install -d /opt/toolchains/rust; \
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}"; \
    rustup component add rust-src --toolchain "${RUST_CHANNEL}"; \
    cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked; \
    rm -f /tmp/rustup-init.sh; \
    # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must
    # read the toolchain and read/refresh the cargo registry cache.
    chown -R 2000:2000 /opt/toolchains/rust; \
    rustc --version; cargo --version; cargo fuzz --version
USER mayhem

# Source enters from the build CONTEXT (CI checkout): the FULL repo (incl. .git) → /mayhem.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz target(s).
RUN bash mayhem/build.sh

# Run the project's functional suite at build time (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
