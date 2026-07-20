#!/bin/sh
set -eu

full_checks='["lock_checksum_sha256","source_transport","git_exact_revision","spdx_license","registry_yanked","registry_vulnerabilities","duplicate_versions","target_match","native_abi","native_target","native_checksum","native_provenance"]'
incomplete_checks='["lock_checksum_sha256","source_transport","git_exact_revision","spdx_license","registry_yanked","registry_vulnerabilities","duplicate_versions","target_match","native_abi","native_target","native_checksum"]'
extra_checks='["lock_checksum_sha256","source_transport","git_exact_revision","spdx_license","registry_yanked","registry_vulnerabilities","duplicate_versions","target_match","native_abi","native_target","native_checksum","native_provenance","future_transparency_log"]'
reverse_extra_checks='["native_provenance","native_checksum","native_target","native_abi","target_match","duplicate_versions","registry_vulnerabilities","registry_yanked","spdx_license","git_exact_revision","source_transport","lock_checksum_sha256","future_signature_format"]'

if [ "${YANBAO_AUDIT_FAKE:-}" = 1 ]; then
  test "$#" -eq 3
  test "$1" = package
  test "$2" = protocol
  scenario=${YANBAO_AUDIT_SCENARIO:?}
  operation_log=${YANBAO_AUDIT_OPERATION_LOG:?}
  project_root=${YANBAO_AUDIT_PROJECT_ROOT:?}
  request=$3
  case "$request" in
    *'"operation":"handshake"'*)
      printf '%s\n' handshake >> "$operation_log"
      case "$scenario" in
        old)
          printf '%s\n' '{"protocol_version":1,"ok":true,"result":{"yanxu_version":"1.1.17","manifest_formats":[1,2],"lock_formats":[1,2],"yxb_formats":[1],"native_abi":[1,2]}}'
          ;;
        incomplete)
          printf '{"protocol_version":1,"ok":true,"result":{"yanxu_version":"1.1.18","manifest_formats":[1,2],"lock_formats":[1,2],"yxb_formats":[1],"native_abi":[1,2],"operation_capabilities":{"audit":{"schema_version":1,"checks":%s}}}}\n' "$incomplete_checks"
          ;;
        invalid-schema)
          printf '{"protocol_version":1,"ok":true,"result":{"yanxu_version":"1.1.18","manifest_formats":[1,2],"lock_formats":[1,2],"yxb_formats":[1],"native_abi":[1,2],"operation_capabilities":{"audit":{"schema_version":2,"checks":%s}}}}\n' "$full_checks"
          ;;
        complete|inconsistent)
          printf '{"protocol_version":1,"ok":true,"result":{"yanxu_version":"1.1.18","manifest_formats":[1,2],"lock_formats":[1,2],"yxb_formats":[1],"native_abi":[1,2],"operation_capabilities":{"audit":{"schema_version":1,"checks":%s}}}}\n' "$full_checks"
          ;;
        extra)
          printf '{"protocol_version":1,"ok":true,"result":{"yanxu_version":"1.1.18","manifest_formats":[1,2],"lock_formats":[1,2],"yxb_formats":[1],"native_abi":[1,2],"operation_capabilities":{"audit":{"schema_version":1,"checks":%s},"future_operation":{"schema_version":7}}}}\n' "$extra_checks"
          ;;
        *) exit 91 ;;
      esac
      ;;
    *'"operation":"inspect"'*)
      printf '%s\n' inspect >> "$operation_log"
      printf '{"protocol_version":1,"ok":true,"result":{"root":"%s"}}\n' "$project_root"
      ;;
    *'"operation":"audit"'*)
      printf '%s\n' audit >> "$operation_log"
      case "$scenario" in
        complete)
          printf '{"protocol_version":1,"ok":true,"result":{"audit_capabilities":{"schema_version":1,"checks":%s},"findings":[]}}\n' "$full_checks"
          ;;
        extra)
          printf '{"protocol_version":1,"ok":true,"result":{"audit_capabilities":{"schema_version":1,"checks":%s},"findings":[],"future_field":true}}\n' "$reverse_extra_checks"
          ;;
        inconsistent)
          printf '{"protocol_version":1,"ok":true,"result":{"audit_capabilities":{"schema_version":1,"checks":%s},"findings":[]}}\n' "$incomplete_checks"
          ;;
        *) exit 92 ;;
      esac
      ;;
    *) exit 93 ;;
  esac
  exit 0
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
execution_root=$(dirname "$root")
runner=${1:-${YANXU_TEST_RUNNER:-}}
if [ -z "$runner" ] || [ ! -x "$runner" ]; then
  echo "用法：test-audit-capability-negotiation.sh <言序程序>" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/yanbao-audit-capability-$$"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_scenario() {
  scenario=$1
  expected_result=$2
  expected_audit_calls=$3
  output="$work/$scenario.json"
  errors="$work/$scenario.log"
  operations="$work/$scenario.operations"
  : > "$operations"
  set +e
  (
    cd "$execution_root"
    YANBAO_AUDIT_FAKE=1 \
    YANBAO_AUDIT_SCENARIO="$scenario" \
    YANBAO_AUDIT_OPERATION_LOG="$operations" \
    YANBAO_AUDIT_PROJECT_ROOT="$root" \
    YANXU_BIN="$script_dir/test-audit-capability-negotiation.sh" \
      "$runner" run "$root/src/主.yx" -- audit --manifest-path "$root" \
        --message-format json
  ) > "$output" 2> "$errors"
  actual_status=$?
  set -e

  audit_calls=$(awk '$0 == "audit" { count += 1 } END { print count + 0 }' "$operations")
  test "$audit_calls" -eq "$expected_audit_calls"
  if [ "$expected_result" = success ]; then
    test "$actual_status" -eq 0
    jq -e '
      .success == true and .exit_code == 0 and
      (.diagnostics | length) == 0 and
      any(.changes[]; .kind == "audit_summary")
    ' "$output" >/dev/null
  else
    test "$actual_status" -ne 0
    jq -e '
      .success == false and .exit_code == 1 and
      any(.diagnostics[]; .code == "AUDIT_CAPABILITY_MISSING") and
      (.changes | length) == 0
    ' "$output" >/dev/null
  fi
}

run_scenario old failure 0
run_scenario incomplete failure 0
run_scenario invalid-schema failure 0
run_scenario complete success 1
run_scenario extra success 1
run_scenario inconsistent failure 1

printf '%s\n' "audit capability negotiation tests passed"
