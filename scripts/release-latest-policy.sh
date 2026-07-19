#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "用法：scripts/release-latest-policy.sh <候选标签>" >&2
  exit 2
fi

candidate=$1
semver_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
for required in awk grep sort tail; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "缺少发行版本比较命令：$required" >&2
    exit 2
  }
done
if ! printf '%s\n' "$candidate" | grep -Eq "$semver_pattern"; then
  echo "候选发行标签必须使用严格 vX.Y.Z 格式：$candidate" >&2
  exit 2
fi

highest=$(
  {
    awk -v pattern="$semver_pattern" '$0 ~ pattern'
    printf '%s\n' "$candidate"
  } | LC_ALL=C sort -V | tail -n 1
)

if [ "$highest" = "$candidate" ]; then
  printf '%s\n' latest
else
  printf '%s\n' not-latest
fi
