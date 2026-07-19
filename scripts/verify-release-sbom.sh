#!/bin/sh
set -eu

if [ "$#" -ne 9 ]; then
  echo "用法：scripts/verify-release-sbom.sh <仓库> <提交> <证明引用> <源码引用> <目标> <归档> <锁文件> <SBOM> <证明包>" >&2
  exit 2
fi

repository=$1
commit=$2
attestation_ref=$3
source_ref=$4
target=$5
archive=$6
lockfile=$7
sbom=$8
bundle=$9
gh_bin=${GH_BIN:-gh}

if ! printf '%s\n' "$commit" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "发行提交摘要无效：$commit" >&2
  exit 2
fi
case "$target" in
  ""|*[!A-Za-z0-9_.-]*) echo "目标名称含非法字符：$target" >&2; exit 2 ;;
esac
for path in "$archive" "$lockfile" "$sbom" "$bundle"; do
  if [ ! -f "$path" ]; then
    echo "SBOM 验证输入不存在：$path" >&2
    exit 2
  fi
done
for required in "$gh_bin" jq; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "缺少 SBOM 验证命令：$required" >&2
    exit 2
  }
done

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

lock_target=$(sed -n 's/^target = "\([^"]*\)"$/\1/p' "$lockfile")
if [ "$lock_target" != "$target" ]; then
  echo "锁文件目标 $lock_target 与发行目标 $target 不一致" >&2
  exit 1
fi
archive_name=$(basename -- "$archive")
archive_sha=$(sha256_file "$archive")
archive_bytes=$(wc -c < "$archive" | tr -d ' ')
lock_sha=$(sha256_file "$lockfile")

verification=$(
  "$gh_bin" attestation verify "$archive" --repo "$repository" \
    --signer-workflow "$repository/.github/workflows/release.yml" \
    --bundle "$bundle" \
    --predicate-type "https://cyclonedx.org/bom" \
    --source-digest "$commit" \
    --source-ref "$attestation_ref" \
    --format json
)

printf '%s\n' "$verification" | jq -e \
  --slurpfile sbom "$sbom" \
  --arg commit "$commit" \
  --arg source_ref "$source_ref" \
  --arg target "$target" \
  --arg archive "$archive_name" \
  --arg archive_sha "$archive_sha" \
  --arg archive_bytes "$archive_bytes" \
  --arg lock_sha "$lock_sha" '
    def property($document; $name; $value):
      ([$document.metadata.component.properties[]? |
        select(.name == $name and .value == $value)] | length) == 1;
    length == 1 and ($sbom | length) == 1 and
    (.[0].verificationResult.statement as $statement |
      $statement.predicateType == "https://cyclonedx.org/bom" and
      $statement.predicate.bomFormat == "CycloneDX" and
      $statement.predicate.specVersion == "1.5" and
      ($statement.predicate.serialNumber |
        test("^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) and
      ($statement.subject | length) == 1 and
      ([ $statement.subject[] |
        select(.name == $archive and .digest.sha256 == $archive_sha) ] | length) == 1 and
      $statement.predicate == $sbom[0] and
      property($statement.predicate; "cdx:yanbao:source:commit"; $commit) and
      property($statement.predicate; "cdx:yanbao:source:ref"; $source_ref) and
      property($statement.predicate; "cdx:yanbao:artifact:name"; $archive) and
      property($statement.predicate; "cdx:yanbao:artifact:sha256"; $archive_sha) and
      property($statement.predicate; "cdx:yanbao:artifact:bytes"; $archive_bytes) and
      property($statement.predicate; "cdx:yanbao:build:target"; $target) and
      property($statement.predicate; "cdx:yanbao:lock:target"; $target) and
      property($statement.predicate; "cdx:yanbao:lock:sha256"; $lock_sha))
  ' >/dev/null
