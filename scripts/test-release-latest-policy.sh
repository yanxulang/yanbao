#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
policy="$script_dir/release-latest-policy.sh"
workflow="$script_dir/../.github/workflows/release.yml"

check_decision() {
  expected=$1
  candidate=$2
  stable_tags=$3
  actual=$(printf '%s' "$stable_tags" | sh "$policy" "$candidate")
  if [ "$actual" != "$expected" ]; then
    echo "候选 ${candidate} 的 latest 决策应为 ${expected}，实际为 ${actual}" >&2
    exit 1
  fi
}

require_workflow_text() {
  expected=$1
  message=$2
  if ! grep -Fq -- "$expected" "$workflow"; then
    echo "$message" >&2
    exit 1
  fi
}

check_decision latest v0.6.1 ''
check_decision latest v0.6.1 'v0.6.1
'
check_decision latest v0.6.1 'v0.5.1
'
check_decision latest v0.10.0 'v0.9.9
'
check_decision not-latest v0.6.1 'v0.7.0
'
check_decision not-latest v0.6.1 'v0.5.1
v0.7.0
'
check_decision not-latest v0.9.9 'v0.10.0
'
check_decision latest v1.0.0 'nightly
v0.99.0
'

if printf '%s\n' v0.6.0 | sh "$policy" v01.0.0 >/dev/null 2>&1; then
  echo "候选标签必须使用严格 vX.Y.Z 格式" >&2
  exit 1
fi

require_workflow_text \
  "sh scripts/release-latest-policy.sh \"\$RELEASE_TAG\"" \
  "正式发布工作流必须调用 latest 版本策略"
require_workflow_text \
  'select(.draft == false and .prerelease == false)' \
  "latest 版本策略只能比较正式稳定 Release"
require_workflow_text \
  "--latest=\"\$latest_flag\"" \
  "正式发布工作流必须显式应用 latest 决策"

printf '%s\n' "release latest policy tests passed"
