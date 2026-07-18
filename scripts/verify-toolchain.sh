#!/bin/sh
set -eu

: "${YANXU_BIN:?YANXU_BIN must point to the Yanxu executable}"
command -v jq >/dev/null 2>&1 || {
  printf '%s\n' "jq is required to verify the Yanxu toolchain" >&2
  exit 1
}

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/yanbao-toolchain-$$"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

"$YANXU_BIN" version --json > "$work/version.json"
actual_version="$(jq -er '.version' "$work/version.json")"
if [ -n "${YANXU_EXPECTED_VERSION:-}" ] && [ "$actual_version" != "$YANXU_EXPECTED_VERSION" ]; then
  printf '%s\n' "expected Yanxu $YANXU_EXPECTED_VERSION, found $actual_version" >&2
  exit 1
fi

jq -e '
  .schema_version == 2
  and (.version | type == "string" and length > 0)
  and ((.manifest_formats | index(2)) != null)
  and ((.lock_formats | index(2)) != null)
  and ((.yxb_formats | index(1)) != null)
  and ((.native_abi | index(1)) != null)
  and ((.native_abi | index(2)) != null)
' "$work/version.json" >/dev/null

"$YANXU_BIN" package protocol \
  '{"protocol_version":1,"operation":"handshake"}' > "$work/handshake.json"
jq -e --arg version "$actual_version" '
  .protocol_version == 1
  and .ok == true
  and .result.yanxu_version == $version
  and ((.result.manifest_formats | index(2)) != null)
  and ((.result.lock_formats | index(2)) != null)
  and ((.result.yxb_formats | index(1)) != null)
  and ((.result.native_abi | index(1)) != null)
  and ((.result.native_abi | index(2)) != null)
  and ((.result.operations | index("handshake")) != null)
  and ((.result.operations | index("bundle")) != null)
  and ((.result.operations | index("vendor")) != null)
' "$work/handshake.json" >/dev/null

export YANXU_BIN
project_root="${YANBAO_ROOT:-.}"
"$YANXU_BIN" check "$project_root/src/主.yx"
"$YANXU_BIN" test "$project_root/tests"
