#!/usr/bin/env bash
#
# typecheck.sh — best-effort Swift verification on the Linux sandbox.
#
# The repo targets macOS only (imports IOKit / AppKit / SwiftUI, none of
# which exist on Linux), so `swift build` cannot link ScarlettCore, let
# alone ScarlettCLI or ScarlettApp.  What it CAN do:
#
#   1. `swiftc -parse <file>` — pure syntax check (catches brace mismatches,
#      stray tokens, malformed statements).  Instant per file.
#   2. `swift build --product scarlett-cli` — SwiftPM compiles each
#      ScarlettCore source file individually.  Real type errors in the
#      file body (typo'd method names, wrong arg counts, missing fields,
#      bad pattern matches) surface before module emission fails on the
#      `no such module 'IOKit'` line.  ScarlettCLI itself does NOT get
#      typechecked (depends on ScarlettCore which can't emit) — verify
#      those edits via `./tooling/run-mac.sh` on the Mac.
#
# Exit code: 0 if both steps clean (allowing for the known IOKit import
# failure), 1 otherwise.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# 1. Parse-check every Swift source in the repo.
echo "→ swiftc -parse (per file)"
parse_fail=0
while IFS= read -r f; do
  if ! swiftc -parse "$f" >/dev/null 2>&1; then
    echo "  ✗ $f"
    swiftc -parse "$f" >&2 || true
    parse_fail=1
  fi
done < <(find Sources -name '*.swift' -type f | sort)
if [[ $parse_fail -ne 0 ]]; then
  exit 1
fi
echo "  ✓ all Swift sources parse cleanly"

# 2. SwiftPM build of ScarlettCore (fails at module emission over IOKit —
#    expected; we only care about body-level type errors).
echo "→ swift build --product scarlett-cli"
build_log="$(mktemp -t scarlett-build.XXXXXX.log)"
trap 'rm -f "$build_log"' EXIT
swift build --product scarlett-cli >"$build_log" 2>&1 || true

# Filter out the known IOKit import error and check for anything else.
real_errors="$(grep -E "error:" "$build_log" \
    | grep -vE "no such module 'IOKit'" \
    | grep -vE "emit-module command failed" || true)"
if [[ -n "$real_errors" ]]; then
  echo "  ✗ real type errors surfaced:"
  echo "$real_errors" | sed 's/^/    /'
  exit 1
fi
echo "  ✓ no real type errors (only the expected IOKit import failure remains)"
exit 0