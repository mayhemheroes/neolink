#!/usr/bin/env bash
#
# neolink/mayhem/build.sh — build neolink_core's cargo-fuzz target as a sanitized
# libFuzzer binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), plus the
# crate's test suite for mayhem/test.sh.
#
# Target (additive cargo-fuzz crate, mayhem/fuzz/fuzz_targets/*.rs — upstream
# ships no fuzz crate):
#   bc_deserialize — the PUBLIC BC-message deserialization surface: raw input
#                    bytes parsed into the BcXml / Extension data model via
#                    yaserde (the parse bc::de performs for every modern BC
#                    message; the internal binary header parser itself is
#                    pub(crate) and not reachable from an additive harness).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# This first (online) build populates the cargo registry under $CARGO_HOME; the
# re-run resolves crates from that cache (the rlenv runtime exports
# CARGO_NET_OFFLINE=true — do NOT hard-code `--offline` here).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10). The rlenv runtime may export
# RUST_DEBUG_FLAGS before re-running build.sh offline; the default only applies
# when it is unset or empty.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# ── DWARF < 4 enforcement ───────────────────────────────────────────────────
# Rust's ASan runtime is compiled with the nightly's bundled LLVM (DWARF 5) and
# is linked before project code; strip its debug sections so the binary's first
# .debug_info CU is our DWARF-2 project code.
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 there too.
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

# The cargo-fuzz crate is ADDITIVE under mayhem/fuzz/ (ported from the old fork's
# crates/core/fuzz — upstream ships no fuzz crate; keeping it under mayhem/ leaves
# the overlay purely additive).
FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(bc_deserialize)
TRIPLE="x86_64-unknown-linux-gnu"

# Rust maps the C-style $SANITIZER_FLAGS contract onto -Zsanitizer: `=` (no colon)
# so an explicit EMPTY value (--build-arg SANITIZER_FLAGS=) builds UNsanitized;
# any address mention keeps ASan (Rust nightly's libFuzzer sanitizer — UBSan is a
# C/C++ instrumentation; Rust's safe subset has no UB).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
RUST_SAN=""
if printf '%s' "$SANITIZER_FLAGS" | grep -q 'address'; then RUST_SAN="-Zsanitizer=address"; fi

# OSS-Fuzz Rust libFuzzer+ASan flags; --cfg fuzzing matches libfuzzer-sys.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing ${RUST_SAN} ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

# Use the image's DEFAULT toolchain (the Dockerfile pinned it); a `+toolchain`
# override would make rustup try to install another channel into /opt/toolchains.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
done

# Resolve the cargo target dir robustly via `cargo metadata`.
TARGET_DIR="$(cargo metadata --no-deps --format-version 1 --manifest-path "$FUZZ_DIR/Cargo.toml" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')"
echo "fuzz target_directory: $TARGET_DIR"

REL="$TARGET_DIR/$TRIPLE/release"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$REL/$t"
  if [ ! -x "$bin" ]; then
    echo "ERROR: expected fuzz binary not found at $bin" >&2
    ls -la "$REL" >&2 || true
    exit 1
  fi
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the project's TEST suite too — with the crate's NORMAL flags (no sanitizer
# RUSTFLAGS) — so mayhem/test.sh only RUNS it, never compiles. The suite lives in
# neolink_core (the root neolink binary crate ships no tests and needs gstreamer).
echo "=== cargo test --no-run -p neolink_core (normal flags, pre-building the test suite) ==="
RUSTFLAGS="" cargo test --no-run -p neolink_core --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/bc_deserialize
