#!/bin/sh
set -eu

export LC_ALL=C

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | awk '{print $1}'
  else
    shasum -a 256 < "$1" | awk '{print $1}'
  fi
}

version_at_least() {
  awk -v actual="$1" -v minimum="$2" 'BEGIN {
    split(actual, a, "."); split(minimum, m, ".");
    for (i = 1; i <= 3; i++) {
      if ((a[i] + 0) > (m[i] + 0)) exit 0;
      if ((a[i] + 0) < (m[i] + 0)) exit 1;
    }
    exit 0;
  }'
}

if [ "$#" -ne 4 ]; then
  echo "用法：scripts/generate-build-metadata.sh <目标> <归档> <独立应用> <输出>" >&2
  exit 2
fi

target=$1
archive=$2
application=$3
output=$4
case "$target" in
  ""|*[!A-Za-z0-9_.-]*) echo "目标名称含非法字符：$target" >&2; exit 2 ;;
esac
for path in "$archive" "$application"; do
  if [ ! -f "$path" ]; then
    echo "构建输入不存在：$path" >&2
    exit 2
  fi
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
manifest="$root/言序.toml"
lockfile=${YANBAO_LOCKFILE:-"$root/言序.lock"}
version=$(sed -n 's/^版本 = "\([^"]*\)"$/\1/p' "$manifest")
requirement=$(sed -n 's/^言序 = "\([^"]*\)"$/\1/p' "$manifest")
minimum_yanxu=${requirement#>=}
expected_compiler_version=${YANXU_EXPECTED_VERSION:-}
expected_compiler_commit=${YANXU_EXPECTED_COMMIT:-}
manifest_format=$(sed -n 's/^格式 = \([0-9][0-9]*\)$/\1/p' "$manifest")
lock_format=$(sed -n 's/^lock_version = \([0-9][0-9]*\)$/\1/p' "$lockfile")
lock_manifest_sha=$(sed -n 's/^manifest_checksum = "\([0-9a-f]*\)"$/\1/p' "$lockfile")
lock_generator=$(sed -n 's/^generator = "\([^"]*\)"$/\1/p' "$lockfile")
lock_target=$(sed -n 's/^target = "\([^"]*\)"$/\1/p' "$lockfile")
manifest_sha=$(sha256_file "$manifest")
lock_sha=$(sha256_file "$lockfile")

if [ -z "$expected_compiler_version" ] || [ -z "$expected_compiler_commit" ]; then
  echo "必须设置预期言序版本 YANXU_EXPECTED_VERSION 和官方标签提交 YANXU_EXPECTED_COMMIT" >&2
  exit 2
fi
for semantic_version in "$version" "$minimum_yanxu" "$expected_compiler_version"; do
  if ! printf '%s\n' "$semantic_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "言包、最低言序或预期编译器版本不是 X.Y.Z" >&2
    exit 2
  fi
done
if ! printf '%s\n' "$expected_compiler_commit" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "预期言序官方标签提交必须是 40 位小写十六进制摘要" >&2
  exit 2
fi
if [ "$requirement" = "$minimum_yanxu" ] || [ -z "$manifest_format" ] || \
   [ -z "$lock_format" ] || [ -z "$lock_manifest_sha" ] || \
   [ -z "$lock_generator" ] || [ -z "$lock_target" ]; then
  echo "清单或锁文件元数据不完整" >&2
  exit 2
fi
if [ "$lock_manifest_sha" != "$manifest_sha" ]; then
  echo "锁文件清单摘要与当前言序.toml 不一致" >&2
  exit 1
fi
if [ "$lock_target" != "$target" ]; then
  echo "锁文件目标 $lock_target 与构建目标 $target 不一致" >&2
  exit 1
fi
if ! version_at_least "$expected_compiler_version" "$minimum_yanxu"; then
  echo "预期言序版本 $expected_compiler_version 低于最低版本 $minimum_yanxu" >&2
  exit 1
fi

compiler=${YANXU_BIN:-}
if [ -z "$compiler" ]; then
  compiler=$(command -v yanxu || true)
fi
if [ -z "$compiler" ]; then
  echo "无法定位言序编译器；请设置 YANXU_BIN" >&2
  exit 2
fi

if ! compiler_info=$("$compiler" version --json); then
  echo "无法读取言序编译器版本：$compiler" >&2
  exit 2
fi
if ! compiler_version=$(printf '%s\n' "$compiler_info" | jq -er '.version'); then
  echo "言序编译器版本信息缺少 version 字段" >&2
  printf '%s\n' "$compiler_info" | jq -c . >&2 || printf '%s\n' "$compiler_info" >&2
  exit 1
fi
if ! compiler_commit=$(printf '%s\n' "$compiler_info" | jq -er '.commit_sha'); then
  echo "言序编译器版本信息缺少 commit_sha 字段" >&2
  printf '%s\n' "$compiler_info" | jq -c . >&2 || printf '%s\n' "$compiler_info" >&2
  exit 1
fi
if ! printf '%s\n' "$compiler_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "言序编译器 version 字段不是 X.Y.Z" >&2
  jq -cn --arg actual "$compiler_version" '{actual: $actual}' >&2
  exit 1
fi
if [ "$compiler_version" != "$expected_compiler_version" ]; then
  echo "言序编译器版本 $compiler_version 与官方标签版本 $expected_compiler_version 不一致" >&2
  exit 1
fi
if [ "$compiler_commit" != "$expected_compiler_commit" ]; then
  echo "言序编译器提交 $compiler_commit 与官方标签提交 $expected_compiler_commit 不一致" >&2
  exit 1
fi
if ! jq -e --arg target "$target" \
  '.build_target == $target and .build_mode == "release"
   and (.commit_sha | test("^[0-9a-f]{40}$"))' >/dev/null <<EOF
$compiler_info
EOF
then
  echo "言序编译器构建目标、模式或提交格式不符合发布要求" >&2
  printf '%s\n' "$compiler_info" | \
    jq -c '{build_target, build_mode, commit_sha}' >&2 || printf '%s\n' "$compiler_info" >&2
  exit 1
fi

if ! application_info=$(YANXU_BIN="$compiler" "$application" --version --message-format json); then
  echo "无法读取独立应用版本信息：$application" >&2
  exit 1
fi
if ! jq -e --arg version "$version" --arg compiler_version "$compiler_version" \
  '.schema_version == 1 and .success == true and .exit_code == 0
   and any(.messages[]; .message == ("言包 " + $version))
   and any(.messages[]; .message == ("言序 " + $compiler_version))' >/dev/null <<EOF
$application_info
EOF
then
  echo "独立应用版本信息未绑定预期言包或言序版本" >&2
  printf '%s\n' "$application_info" | jq -c . >&2 || printf '%s\n' "$application_info" >&2
  exit 1
fi

commit_sha=$(git -C "$root" rev-parse HEAD)
source_epoch=$(git -C "$root" show -s --format=%ct HEAD)
archive_sha=$(sha256_file "$archive")
application_sha=$(sha256_file "$application")
archive_bytes=$(wc -c < "$archive" | tr -d ' ')
application_bytes=$(wc -c < "$application" | tr -d ' ')

mkdir -p "$(dirname -- "$output")"
jq -S -n \
  --arg version "$version" \
  --arg minimum_yanxu "$minimum_yanxu" \
  --arg repository "${GITHUB_REPOSITORY:-YanXuLang/yanbao}" \
  --arg source_ref "${YANBAO_SOURCE_REF:-${GITHUB_REF:-refs/tags/v$version}}" \
  --arg commit "$commit_sha" \
  --arg source_epoch "$source_epoch" \
  --arg target "$target" \
  --arg archive_name "$(basename -- "$archive")" \
  --arg archive_sha "$archive_sha" \
  --argjson archive_bytes "$archive_bytes" \
  --arg application_name "$(basename -- "$application")" \
  --arg application_sha "$application_sha" \
  --argjson application_bytes "$application_bytes" \
  --arg manifest_format "$manifest_format" \
  --arg manifest_sha "$manifest_sha" \
  --arg lock_format "$lock_format" \
  --arg lock_generator "$lock_generator" \
  --arg lock_target "$lock_target" \
  --arg lock_sha "$lock_sha" \
  --arg compiler_source_ref "refs/tags/v$expected_compiler_version" \
  --argjson compiler "$compiler_info" \
  '{
    schema_version: 1,
    version: $version,
    minimum_yanxu_version: $minimum_yanxu,
    source: {
      repository: $repository,
      ref: $source_ref,
      commit_sha: $commit,
      commit_timestamp: ($source_epoch | tonumber)
    },
    artifact: {
      name: $archive_name,
      sha256: $archive_sha,
      bytes: $archive_bytes
    },
    application: {
      name: $application_name,
      sha256: $application_sha,
      bytes: $application_bytes,
      version_info: {
        version: $version,
        yanxu_version: $compiler.version
      }
    },
    build: {
      target: $target,
      profile: "release",
      standalone: true,
      separate_runtime_bundled: false,
      manifest: {
        format: ($manifest_format | tonumber),
        sha256: $manifest_sha
      },
      lock: {
        format: ($lock_format | tonumber),
        manifest_sha256: $manifest_sha,
        generator: $lock_generator,
        target: $lock_target,
        sha256: $lock_sha
      },
      compiler: {
        name: "yanxu",
        version: $compiler.version,
        source_ref: $compiler_source_ref,
        commit_sha: $compiler.commit_sha,
        target: $compiler.build_target,
        mode: $compiler.build_mode
      }
    }
  }' > "$output.tmp"
mv "$output.tmp" "$output"

if ! jq -e \
  --arg version "$version" \
  --arg minimum_yanxu "$minimum_yanxu" \
  --arg commit "$commit_sha" \
  --arg target "$target" \
  --arg compiler_version "$expected_compiler_version" \
  --arg compiler_ref "refs/tags/v$expected_compiler_version" \
  --arg compiler_commit "$expected_compiler_commit" \
  '.schema_version == 1 and .version == $version
   and .minimum_yanxu_version == $minimum_yanxu
   and .source.commit_sha == $commit
   and .build.target == $target and .build.profile == "release"
   and .build.standalone and (.build.separate_runtime_bundled | not)
   and .build.lock.target == $target and .build.lock.manifest_sha256 == .build.manifest.sha256
   and .build.compiler.version == $compiler_version
   and .build.compiler.source_ref == $compiler_ref
   and .build.compiler.commit_sha == $compiler_commit
   and .build.compiler.target == $target and .build.compiler.mode == "release"
   and (.artifact.sha256 | test("^[0-9a-f]{64}$"))
   and (.application.sha256 | test("^[0-9a-f]{64}$"))
   and (.build.manifest.sha256 | test("^[0-9a-f]{64}$"))
   and (.build.lock.sha256 | test("^[0-9a-f]{64}$"))' "$output" >/dev/null
then
  echo "生成的构建元数据未通过自校验" >&2
  jq -c . "$output" >&2 || true
  exit 1
fi

if grep -F "$root" "$output" >/dev/null; then
  echo "构建元数据不得包含构建机绝对路径" >&2
  exit 1
fi
