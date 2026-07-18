#!/bin/sh
set -eu

export LC_ALL=C

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
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
lockfile="$root/言序.lock"
version=$(sed -n 's/^版本 = "\([^"]*\)"$/\1/p' "$manifest")
requirement=$(sed -n 's/^言序 = "\([^"]*\)"$/\1/p' "$manifest")
minimum_yanxu=${requirement#>=}
manifest_format=$(sed -n 's/^格式 = \([0-9][0-9]*\)$/\1/p' "$manifest")
lock_format=$(sed -n 's/^lock_version = \([0-9][0-9]*\)$/\1/p' "$lockfile")
lock_generator=$(sed -n 's/^generator = "\([^"]*\)"$/\1/p' "$lockfile")
lock_target=$(sed -n 's/^target = "\([^"]*\)"$/\1/p' "$lockfile")

for semantic_version in "$version" "$minimum_yanxu"; do
  if ! printf '%s\n' "$semantic_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "言包或最低言序版本不是 X.Y.Z" >&2
    exit 2
  fi
done
if [ "$requirement" = "$minimum_yanxu" ] || [ -z "$manifest_format" ] || \
   [ -z "$lock_format" ] || [ -z "$lock_generator" ] || [ -z "$lock_target" ]; then
  echo "清单或锁文件元数据不完整" >&2
  exit 2
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
compiler_version=$(printf '%s\n' "$compiler_info" | jq -er '.version')
printf '%s\n' "$compiler_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
if ! version_at_least "$compiler_version" "$minimum_yanxu"; then
  echo "言序编译器 $compiler_version 低于最低版本 $minimum_yanxu" >&2
  exit 1
fi
jq -e --arg target "$target" \
  '.build_target == $target and .build_mode == "release"
   and (.commit_sha | test("^[0-9a-f]{40}$"))' >/dev/null <<EOF
$compiler_info
EOF

application_info=$(YANXU_BIN="$compiler" "$application" --version --message-format json)
jq -e --arg version "$version" --arg compiler_version "$compiler_version" \
  '.schema_version == 1 and .success == true and .exit_code == 0
   and any(.messages[]; .message == ("言包 " + $version))
   and any(.messages[]; .message == ("言序 " + $compiler_version))' >/dev/null <<EOF
$application_info
EOF

commit_sha=$(git -C "$root" rev-parse HEAD)
source_epoch=$(git -C "$root" show -s --format=%ct HEAD)
manifest_sha=$(sha256_file "$manifest")
lock_sha=$(sha256_file "$lockfile")
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
        generator: $lock_generator,
        target: $lock_target,
        sha256: $lock_sha
      },
      compiler: {
        name: "yanxu",
        version: $compiler.version,
        commit_sha: $compiler.commit_sha,
        target: $compiler.build_target,
        mode: $compiler.build_mode
      }
    }
  }' > "$output.tmp"
mv "$output.tmp" "$output"

jq -e \
  --arg version "$version" \
  --arg minimum_yanxu "$minimum_yanxu" \
  --arg commit "$commit_sha" \
  --arg target "$target" \
  '.schema_version == 1 and .version == $version
   and .minimum_yanxu_version == $minimum_yanxu
   and .source.commit_sha == $commit
   and .build.target == $target and .build.profile == "release"
   and .build.standalone and (.build.separate_runtime_bundled | not)
   and .build.compiler.target == $target and .build.compiler.mode == "release"
   and (.artifact.sha256 | test("^[0-9a-f]{64}$"))
   and (.application.sha256 | test("^[0-9a-f]{64}$"))
   and (.build.manifest.sha256 | test("^[0-9a-f]{64}$"))
   and (.build.lock.sha256 | test("^[0-9a-f]{64}$"))' "$output" >/dev/null

if grep -F "$root" "$output" >/dev/null; then
  echo "构建元数据不得包含构建机绝对路径" >&2
  exit 1
fi
