#!/usr/bin/env bash
#
# neolink/mayhem/test.sh — RUN neolink's own upstream test suite (`cargo test -p
# neolink_core`) and emit a CTRF summary. exit 0 iff no test failed.
#
# The suite is the repo's ENTIRE upstream test set: every #[test] in the repo
# lives in the neolink_core crate (bc/bcudp/bcmedia (de)serializers, xml,
# xml_crypto — assert_matches/known-answer assertions on concrete protocol
# bytes), plus its doc-tests. The root `neolink` binary crate ships NO tests
# (and links gstreamer). These are behavioral known-answer tests — a no-op /
# exit(0) patch cannot pass them.
#
# build.sh pre-compiled the suite with the crate's NORMAL flags (cargo test
# --no-run); this script only RUNS it.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

echo "=== running cargo test -p neolink_core (upstream suite) ==="
# Image-default toolchain; --no-fail-fast so we count every test; RUSTFLAGS cleared
# so it inherits nothing from the sanitizer build (matches build.sh's --no-run build).
out="$(RUSTFLAGS="" cargo test -p neolink_core --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"

# libtest prints one line per test binary:
#   test result: ok. 41 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; ...
# Sum across all binaries (lib tests + doc-tests).
PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n' "$out" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

# If we parsed no result lines, fall back to the cargo exit code (e.g. compile error).
if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse any 'test result:' lines; using cargo exit code $rc" >&2
  [ "$rc" -eq 0 ] && { emit_ctrf "cargo-test" 1 0 0; exit 0; }
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
