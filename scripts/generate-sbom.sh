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

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

if [ "$#" -ne 3 ]; then
  echo "用法：scripts/generate-sbom.sh <目标> <归档> <输出>" >&2
  exit 2
fi

target=$1
archive=$2
output=$3
case "$target" in
  ""|*[!A-Za-z0-9_.-]*) echo "目标名称含非法字符：$target" >&2; exit 2 ;;
esac
if [ ! -f "$archive" ]; then
  echo "SBOM 对应归档不存在：$archive" >&2
  exit 2
fi
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
manifest="$root/言序.toml"
lockfile=${YANBAO_LOCKFILE:-"$root/言序.lock"}

version=$(sed -n 's/^版本 = "\([^"]*\)"$/\1/p' "$manifest")
requirement=$(sed -n 's/^言序 = "\([^"]*\)"$/\1/p' "$manifest")
license=$(sed -n 's/^许可 = "\([^"]*\)"$/\1/p' "$manifest")
minimum_yanxu=${requirement#>=}
manifest_format=$(sed -n 's/^格式 = \([0-9][0-9]*\)$/\1/p' "$manifest")
lock_format=$(sed -n 's/^lock_version = \([0-9][0-9]*\)$/\1/p' "$lockfile")
lock_manifest_sha=$(sed -n 's/^manifest_checksum = "\([0-9a-f]*\)"$/\1/p' "$lockfile")
lock_generator=$(sed -n 's/^generator = "\([^"]*\)"$/\1/p' "$lockfile")
lock_target=$(sed -n 's/^target = "\([^"]*\)"$/\1/p' "$lockfile")
manifest_sha=$(sha256_file "$manifest")
lock_sha=$(sha256_file "$lockfile")

for semantic_version in "$version" "$minimum_yanxu"; do
  if ! printf '%s\n' "$semantic_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "言包或最低言序版本不是 X.Y.Z" >&2
    exit 2
  fi
done
if [ "$requirement" = "$minimum_yanxu" ] || [ "$license" != "MIT" ]; then
  echo "清单必须声明 >=X.Y.Z 言序运行时和 MIT 许可" >&2
  exit 2
fi
if [ -z "$manifest_format" ] || [ -z "$lock_format" ] || \
   [ -z "$lock_manifest_sha" ] || [ -z "$lock_generator" ] || [ -z "$lock_target" ]; then
  echo "清单或锁文件元数据不完整" >&2
  exit 2
fi
if [ "$lock_manifest_sha" != "$manifest_sha" ]; then
  echo "锁文件清单摘要与当前言序.toml 不一致" >&2
  exit 1
fi
if [ "$lock_target" != "$target" ]; then
  echo "锁文件目标 $lock_target 与 SBOM 目标 $target 不一致" >&2
  exit 1
fi

commit_sha=$(git -C "$root" rev-parse HEAD)
commit_timestamp=$(git -C "$root" show -s --format=%cI HEAD)
serial_seed=$(printf '%s:%s\n' "$commit_sha" "$target" | sha256_text)
serial_number=$(printf '%s\n' "$serial_seed" | sed -E \
  's/^(.{8})(.{4}).(.{3}).(.{3})(.{12}).*$/urn:uuid:\1-\2-8\3-a\4-\5/')
if ! printf '%s\n' "$serial_number" | grep -Eq \
  '^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'; then
  echo "不能从提交与目标生成 CycloneDX 序列号" >&2
  exit 1
fi
source_ref=${YANBAO_SOURCE_REF:-${GITHUB_REF:-refs/tags/v$version}}
repository=${GITHUB_REPOSITORY:-YanXuLang/yanbao}
component_ref="pkg:github/YanXuLang/yanbao@$version"
runtime_ref="pkg:github/YanXuLang/yanxu@$minimum_yanxu"
archive_name=$(basename -- "$archive")
archive_sha=$(sha256_file "$archive")
archive_bytes=$(wc -c < "$archive" | tr -d ' ')

mkdir -p "$(dirname -- "$output")"
jq -S -n \
  --arg version "$version" \
  --arg minimum_yanxu "$minimum_yanxu" \
  --arg license "$license" \
  --arg repository "$repository" \
  --arg source_ref "$source_ref" \
  --arg commit "$commit_sha" \
  --arg serial_number "$serial_number" \
  --arg timestamp "$commit_timestamp" \
  --arg manifest_format "$manifest_format" \
  --arg manifest_sha "$manifest_sha" \
  --arg target "$target" \
  --arg archive_name "$archive_name" \
  --arg archive_sha "$archive_sha" \
  --arg archive_bytes "$archive_bytes" \
  --arg lock_format "$lock_format" \
  --arg lock_generator "$lock_generator" \
  --arg lock_target "$lock_target" \
  --arg lock_sha "$lock_sha" \
  --arg component_ref "$component_ref" \
  --arg runtime_ref "$runtime_ref" \
  '{
    "$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json",
    bomFormat: "CycloneDX",
    specVersion: "1.5",
    serialNumber: $serial_number,
    version: 1,
    metadata: {
      timestamp: $timestamp,
      component: {
        type: "application",
        "bom-ref": $component_ref,
        group: "YanXuLang",
        name: "yanbao",
        version: $version,
        licenses: [{license: {id: $license}}],
        purl: $component_ref,
        externalReferences: [{
          type: "vcs",
          url: ("https://github.com/" + $repository + ".git#" + $commit)
        }],
        properties: [
          {name: "cdx:yanbao:source:ref", value: $source_ref},
          {name: "cdx:yanbao:source:commit", value: $commit},
          {name: "cdx:yanbao:manifest:format", value: $manifest_format},
          {name: "cdx:yanbao:manifest:sha256", value: $manifest_sha},
          {name: "cdx:yanbao:artifact:name", value: $archive_name},
          {name: "cdx:yanbao:artifact:sha256", value: $archive_sha},
          {name: "cdx:yanbao:artifact:bytes", value: $archive_bytes},
          {name: "cdx:yanbao:build:target", value: $target},
          {name: "cdx:yanbao:lock:format", value: $lock_format},
          {name: "cdx:yanbao:lock:manifest-sha256", value: $manifest_sha},
          {name: "cdx:yanbao:lock:generator", value: $lock_generator},
          {name: "cdx:yanbao:lock:target", value: $lock_target},
          {name: "cdx:yanbao:lock:sha256", value: $lock_sha},
          {name: "cdx:yanbao:build:profile", value: "release"}
        ]
      }
    },
    components: [{
      type: "application",
      "bom-ref": $runtime_ref,
      group: "YanXuLang",
      name: "yanxu",
      version: $minimum_yanxu,
      scope: "required",
      licenses: [{license: {id: "MIT"}}],
      purl: $runtime_ref,
      properties: [
        {name: "cdx:yanbao:dependency:role", value: "minimum-compatible-runtime"},
        {name: "cdx:yanbao:dependency:requirement", value: (">=" + $minimum_yanxu)}
      ]
    }],
    dependencies: [
      {ref: $component_ref, dependsOn: [$runtime_ref]},
      {ref: $runtime_ref, dependsOn: []}
    ]
  }' > "$output.tmp"

jq -e \
  --arg version "$version" \
  --arg minimum_yanxu "$minimum_yanxu" \
  --arg commit "$commit_sha" \
  --arg serial_number "$serial_number" \
  --arg manifest_sha "$manifest_sha" \
  --arg target "$target" \
  --arg archive_name "$archive_name" \
  --arg archive_sha "$archive_sha" \
  --arg archive_bytes "$archive_bytes" \
  --arg lock_sha "$lock_sha" \
  '.bomFormat == "CycloneDX" and .specVersion == "1.5"
   and .serialNumber == $serial_number and .version == 1
   and .metadata.component.name == "yanbao" and .metadata.component.version == $version
   and (.metadata.component.licenses == [{license: {id: "MIT"}}])
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:source:commit" and .value == $commit)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:manifest:sha256" and .value == $manifest_sha)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:artifact:name" and .value == $archive_name)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:artifact:sha256" and .value == $archive_sha)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:artifact:bytes" and .value == $archive_bytes)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:build:target" and .value == $target)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:lock:target" and .value == $target)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:lock:manifest-sha256" and .value == $manifest_sha)] | length) == 1
   and ([.metadata.component.properties[] |
     select(.name == "cdx:yanbao:lock:sha256" and .value == $lock_sha)] | length) == 1
   and ([.components[] |
     select(.name == "yanxu" and .version == $minimum_yanxu and .scope == "required")] | length) == 1
   and (.dependencies | length) == 2' "$output.tmp" >/dev/null

if grep -F "$root" "$output.tmp" >/dev/null; then
  echo "SBOM 不得包含构建机绝对路径" >&2
  exit 1
fi
mv "$output.tmp" "$output"
