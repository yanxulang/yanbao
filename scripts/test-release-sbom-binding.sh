#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
generator="$script_dir/generate-sbom.sh"
verifier="$script_dir/verify-release-sbom.sh"
workflow="$root/.github/workflows/release.yml"
work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/yanbao-sbom-binding-$$"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

make_verification() {
  sbom=$1
  archive=$2
  output=$3
  archive_name=$(basename -- "$archive")
  archive_sha=$(sha256_file "$archive")
  jq -c -n --slurpfile sbom "$sbom" \
    --arg archive "$archive_name" --arg archive_sha "$archive_sha" \
    '[{
      verificationResult: {
        statement: {
          predicateType: "https://cyclonedx.org/bom",
          subject: [{name: $archive, digest: {sha256: $archive_sha}}],
          predicate: $sbom[0]
        }
      }
    }]' > "$output"
}

fake_gh="$work/gh"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'arguments=" $* "' \
  'for required in " attestation verify " " --signer-workflow " " --bundle " " --predicate-type " " --source-digest " " --source-ref " " --format json "; do' \
  "  case \"\$arguments\" in *\"\$required\"*) ;; *) exit 91 ;; esac" \
  'done' \
  "exec jq -c . \"\$YANBAO_TEST_VERIFICATION\"" \
  > "$fake_gh"
chmod 755 "$fake_gh"
: > "$work/bundle.jsonl"

targets='x86_64-unknown-linux-gnu
aarch64-unknown-linux-gnu
x86_64-apple-darwin
aarch64-apple-darwin
x86_64-pc-windows-msvc
aarch64-pc-windows-msvc'
serials="$work/serials"
: > "$serials"
commit=$(git -C "$root" rev-parse HEAD)
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
  case "$target" in
    *windows*) archive="$work/yanbao-$target.zip" ;;
    *) archive="$work/yanbao-$target.tar.gz" ;;
  esac
  printf 'archive fixture for %s\n' "$target" > "$archive"
  sbom="$work/yanbao-$target.cdx.json"
  YANBAO_SOURCE_REF=refs/tags/v0.6.0 YANBAO_LOCKFILE="$lockfile" \
    sh "$generator" "$target" "$archive" "$sbom"

  archive_name=$(basename -- "$archive")
  archive_sha=$(sha256_file "$archive")
  lock_sha=$(sha256_file "$lockfile")
  jq -e --arg target "$target" --arg archive "$archive_name" \
    --arg archive_sha "$archive_sha" --arg lock_sha "$lock_sha" '
      def property($name; $value):
        ([.metadata.component.properties[] |
          select(.name == $name and .value == $value)] | length) == 1;
      property("cdx:yanbao:artifact:name"; $archive) and
      property("cdx:yanbao:artifact:sha256"; $archive_sha) and
      property("cdx:yanbao:lock:target"; $target) and
      property("cdx:yanbao:lock:sha256"; $lock_sha)
    ' "$sbom" >/dev/null
  jq -r .serialNumber "$sbom" >> "$serials"

  verification="$work/yanbao-$target.verification.json"
  make_verification "$sbom" "$archive" "$verification"
  GH_BIN="$fake_gh" YANBAO_TEST_VERIFICATION="$verification" \
    sh "$verifier" YanXuLang/yanbao "$commit" refs/tags/v0.6.0 refs/tags/v0.6.0 \
      "$target" "$archive" "$lockfile" "$sbom" "$work/bundle.jsonl"
done

test "$(LC_ALL=C sort -u "$serials" | wc -l | tr -d ' ')" -eq 6

first_target=x86_64-unknown-linux-gnu
second_target=aarch64-unknown-linux-gnu
first_archive="$work/yanbao-$first_target.tar.gz"
first_lock="$work/yanbao-$first_target.lock"
first_sbom="$work/yanbao-$first_target.cdx.json"
second_archive="$work/yanbao-$second_target.tar.gz"
second_sbom="$work/yanbao-$second_target.cdx.json"

if YANBAO_SOURCE_REF=refs/tags/v0.6.0 YANBAO_LOCKFILE="$first_lock" \
  sh "$generator" "$second_target" \
  "$second_archive" "$work/mismatched-target.cdx.json" >/dev/null 2>&1
then
  echo "SBOM 生成必须拒绝目标与锁文件不一致" >&2
  exit 1
fi

swapped_verification="$work/swapped.verification.json"
make_verification "$second_sbom" "$first_archive" "$swapped_verification"
if GH_BIN="$fake_gh" YANBAO_TEST_VERIFICATION="$swapped_verification" \
  sh "$verifier" YanXuLang/yanbao "$commit" refs/tags/v0.6.0 refs/tags/v0.6.0 \
    "$first_target" "$first_archive" "$first_lock" "$second_sbom" "$work/bundle.jsonl" \
    >/dev/null 2>&1
then
  echo "SBOM 验证必须拒绝交换的平台谓词" >&2
  exit 1
fi

wrong_subject_verification="$work/wrong-subject.verification.json"
make_verification "$first_sbom" "$first_archive" "$wrong_subject_verification"
jq '.[0].verificationResult.statement.subject[0].name = "wrong-platform.tar.gz"' \
  "$wrong_subject_verification" > "$wrong_subject_verification.tmp"
mv "$wrong_subject_verification.tmp" "$wrong_subject_verification"
if GH_BIN="$fake_gh" YANBAO_TEST_VERIFICATION="$wrong_subject_verification" \
  sh "$verifier" YanXuLang/yanbao "$commit" refs/tags/v0.6.0 refs/tags/v0.6.0 \
    "$first_target" "$first_archive" "$first_lock" "$first_sbom" "$work/bundle.jsonl" \
    >/dev/null 2>&1
then
  echo "SBOM 验证必须拒绝错误的签名主体名称" >&2
  exit 1
fi

first_verification="$work/first.verification.json"
make_verification "$first_sbom" "$first_archive" "$first_verification"
printf '%s\n' '# lock tamper' >> "$first_lock"
if GH_BIN="$fake_gh" YANBAO_TEST_VERIFICATION="$first_verification" \
  sh "$verifier" YanXuLang/yanbao "$commit" refs/tags/v0.6.0 refs/tags/v0.6.0 \
    "$first_target" "$first_archive" "$first_lock" "$first_sbom" "$work/bundle.jsonl" \
    >/dev/null 2>&1
then
  echo "SBOM 验证必须拒绝变化后的锁文件" >&2
  exit 1
fi

second_verification="$work/second.verification.json"
make_verification "$second_sbom" "$second_archive" "$second_verification"
printf '%s\n' 'archive tamper' >> "$second_archive"
if GH_BIN="$fake_gh" YANBAO_TEST_VERIFICATION="$second_verification" \
  sh "$verifier" YanXuLang/yanbao "$commit" refs/tags/v0.6.0 refs/tags/v0.6.0 \
    "$second_target" "$second_archive" "$work/yanbao-$second_target.lock" \
    "$second_sbom" "$work/bundle.jsonl" >/dev/null 2>&1
then
  echo "SBOM 验证必须拒绝变化后的归档" >&2
  exit 1
fi

test "$(grep -c 'sbom-path: dist/yanbao-' "$workflow")" -eq 6
test "$(grep -c 'sh scripts/verify-release-sbom.sh' "$workflow")" -eq 3
grep -Fq '(.assets | length) != 32' "$workflow"
if grep -Fq "dist/yanbao-\$VERSION.cdx.json" "$workflow"; then
  echo "正式发布不得继续复用单一版本级 SBOM" >&2
  exit 1
fi
if grep -En 'generate-sbom\.sh[[:space:]]+[^[:space:]]+\.cdx\.json' \
  "$root/README.md" "$root/CONTRIBUTING.md" >/dev/null
then
  echo "文档不得继续使用旧的一参数 SBOM 接口" >&2
  exit 1
fi

printf '%s\n' "release SBOM binding tests passed"
