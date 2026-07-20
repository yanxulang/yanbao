#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
generator="$script_dir/generate-build-metadata.sh"
ci_workflow="$root/.github/workflows/ci.yml"
release_workflow="$root/.github/workflows/release.yml"
work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/yanbao-build-metadata-compiler-$$"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | awk '{print $1}'
  else
    shasum -a 256 < "$1" | awk '{print $1}'
  fi
}

yanbao_version=$(sed -n 's/^版本 = "\([^"]*\)"$/\1/p' "$root/言序.toml")
compiler_version=$(sed -n 's/^言序 = ">=\([^"]*\)"$/\1/p' "$root/言序.toml")
expected_commit=0123456789abcdef0123456789abcdef01234567
different_commit=89abcdef0123456789abcdef0123456789abcdef

fake_compiler="$work/yanxu"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'test "$#" -eq 2' \
  'test "$1" = version' \
  'test "$2" = --json' \
  'exec jq -c . "$YANBAO_TEST_COMPILER_INFO"' \
  > "$fake_compiler"
chmod 755 "$fake_compiler"

fake_application="$work/yanbao-app"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'test "$#" -eq 3' \
  'test "$1" = --version' \
  'test "$2" = --message-format' \
  'test "$3" = json' \
  'exec jq -c . "$YANBAO_TEST_APPLICATION_INFO"' \
  > "$fake_application"
chmod 755 "$fake_application"

application_info="$work/application-info.json"
jq -n --arg version "$yanbao_version" --arg compiler "$compiler_version" \
  '{
    schema_version: 1,
    success: true,
    exit_code: 0,
    messages: [
      {message: ("言包 " + $version)},
      {message: ("言序 " + $compiler)}
    ]
  }' > "$application_info"

targets='x86_64-unknown-linux-gnu
aarch64-unknown-linux-gnu
x86_64-apple-darwin
aarch64-apple-darwin
x86_64-pc-windows-msvc
aarch64-pc-windows-msvc'

manifest_sha=$(sha256_file "$root/言序.toml")
base_lock="$work/base.lock"
{
  printf 'lock_version = 2\n'
  printf 'manifest_checksum = "%s"\n' "$manifest_sha"
  printf 'target = "x86_64-unknown-linux-gnu"\n'
  printf 'generator = "1.1.18"\n'
  printf 'package = []\n\n[root_dependencies]\n\n[root_dev_dependencies]\n'
} > "$base_lock"

for target in $targets; do
  lockfile="$work/yanbao-$target.lock"
  sed "s/^target = \".*\"$/target = \"$target\"/" "$base_lock" > "$lockfile"
  archive="$work/yanbao-$target.archive"
  case "$target" in
    *-pc-windows-msvc)
      windows_temp="$work/D:\\a\\_temp"
      mkdir -p "$windows_temp"
      archive="$windows_temp/yanbao-$target.archive"
      ;;
  esac
  printf 'archive fixture for %s\n' "$target" > "$archive"
  compiler_info="$work/yanxu-$target.json"
  jq -n --arg version "$compiler_version" --arg commit "$expected_commit" \
    --arg target "$target" \
    '{
      schema_version: 2,
      version: $version,
      commit_sha: $commit,
      build_target: $target,
      build_mode: "release"
    }' > "$compiler_info"
  metadata="$work/yanbao-$target.build.json"
  YANBAO_LOCKFILE="$lockfile" \
  YANXU_BIN="$fake_compiler" \
  YANXU_EXPECTED_VERSION="$compiler_version" \
  YANXU_EXPECTED_COMMIT="$expected_commit" \
  YANBAO_TEST_COMPILER_INFO="$compiler_info" \
  YANBAO_TEST_APPLICATION_INFO="$application_info" \
    sh "$generator" "$target" "$archive" "$fake_application" "$metadata"
  jq -e \
    --arg archive_sha "$(sha256_file "$archive")" \
    --arg version "$compiler_version" \
    --arg ref "refs/tags/v$compiler_version" \
    --arg commit "$expected_commit" \
    --arg target "$target" \
    '.artifact.sha256 == $archive_sha
     and (.artifact.sha256 | test("^[0-9a-f]{64}$"))
     and .build.compiler.version == $version
     and .build.compiler.source_ref == $ref
     and .build.compiler.commit_sha == $commit
     and .build.compiler.target == $target' \
    "$metadata" >/dev/null
done

target=x86_64-unknown-linux-gnu
lockfile="$work/yanbao-$target.lock"
archive="$work/yanbao-$target.archive"
compiler_info="$work/yanxu-$target.json"
mismatch="$work/mismatched-compiler.build.json"
mismatched_compiler_info="$work/mismatched-compiler.json"
jq -n --arg version "$compiler_version" --arg commit "$different_commit" \
  --arg target "$target" \
  '{
    schema_version: 2,
    version: $version,
    commit_sha: $commit,
    build_target: $target,
    build_mode: "release"
  }' > "$mismatched_compiler_info"
if YANBAO_LOCKFILE="$lockfile" \
  YANXU_BIN="$fake_compiler" \
  YANXU_EXPECTED_VERSION="$compiler_version" \
  YANXU_EXPECTED_COMMIT="$expected_commit" \
  YANBAO_TEST_COMPILER_INFO="$mismatched_compiler_info" \
  YANBAO_TEST_APPLICATION_INFO="$application_info" \
    sh "$generator" "$target" "$archive" "$fake_application" "$mismatch" \
    >/dev/null 2>&1
then
  echo "构建元数据必须拒绝版本相同但提交不属于官方标签的编译器" >&2
  exit 1
fi
test ! -e "$mismatch"

wrong_version_info="$work/wrong-version-compiler.json"
jq -n --arg version 9.9.9 --arg commit "$expected_commit" --arg target "$target" \
  '{
    schema_version: 2,
    version: $version,
    commit_sha: $commit,
    build_target: $target,
    build_mode: "release"
  }' > "$wrong_version_info"
wrong_version_metadata="$work/wrong-version.build.json"
if YANBAO_LOCKFILE="$lockfile" \
  YANXU_BIN="$fake_compiler" \
  YANXU_EXPECTED_VERSION="$compiler_version" \
  YANXU_EXPECTED_COMMIT="$expected_commit" \
  YANBAO_TEST_COMPILER_INFO="$wrong_version_info" \
  YANBAO_TEST_APPLICATION_INFO="$application_info" \
    sh "$generator" "$target" "$archive" "$fake_application" \
      "$wrong_version_metadata" >/dev/null 2>&1
then
  echo "构建元数据必须拒绝不属于预期官方标签版本的编译器" >&2
  exit 1
fi
test ! -e "$wrong_version_metadata"

missing_expectation="$work/missing-expectation.build.json"
if YANBAO_LOCKFILE="$lockfile" \
  YANXU_BIN="$fake_compiler" \
  YANXU_EXPECTED_VERSION="$compiler_version" \
  YANXU_EXPECTED_COMMIT='' \
  YANBAO_TEST_COMPILER_INFO="$compiler_info" \
  YANBAO_TEST_APPLICATION_INFO="$application_info" \
    sh "$generator" "$target" "$archive" "$fake_application" \
      "$missing_expectation" >/dev/null 2>&1
then
  echo "构建元数据必须要求显式官方标签提交" >&2
  exit 1
fi
test ! -e "$missing_expectation"

# shellcheck disable=SC2016
for marker in \
  'stable_commit: ${{ steps.versions.outputs.stable_commit }}' \
  'YANXU_EXPECTED_COMMIT: ${{ needs.toolchain-versions.outputs.stable_commit }}'
do
  grep -Fq "$marker" "$ci_workflow"
done
# shellcheck disable=SC2016
for marker in \
  'yanxu_commit: ${{ steps.metadata.outputs.yanxu_commit }}' \
  'YANXU_EXPECTED_COMMIT: ${{ needs.validate.outputs.yanxu_commit }}' \
  'repos/YanXuLang/yanxu/commits/$yanxu_tag' \
  '"refs/tags/$RELEASE_TAG"|refs/heads/main)'
do
  grep -Fq "$marker" "$release_workflow"
done
test "$(grep -c 'and .build.compiler.commit_sha ==' "$release_workflow")" -eq 3

printf '%s\n' "build metadata compiler binding tests passed"
