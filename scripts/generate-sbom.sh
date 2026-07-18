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

if [ "$#" -ne 1 ]; then
  echo "用法：scripts/generate-sbom.sh <输出>" >&2
  exit 2
fi

output=$1
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
manifest="$root/言序.toml"
lockfile="$root/言序.lock"

version=$(sed -n 's/^版本 = "\([^"]*\)"$/\1/p' "$manifest")
requirement=$(sed -n 's/^言序 = "\([^"]*\)"$/\1/p' "$manifest")
license=$(sed -n 's/^许可 = "\([^"]*\)"$/\1/p' "$manifest")
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
if [ "$requirement" = "$minimum_yanxu" ] || [ "$license" != "MIT" ]; then
  echo "清单必须声明 >=X.Y.Z 言序运行时和 MIT 许可" >&2
  exit 2
fi
if [ -z "$manifest_format" ] || [ -z "$lock_format" ] || [ -z "$lock_generator" ] || [ -z "$lock_target" ]; then
  echo "清单或锁文件元数据不完整" >&2
  exit 2
fi

commit_sha=$(git -C "$root" rev-parse HEAD)
commit_timestamp=$(git -C "$root" show -s --format=%cI HEAD)
serial_number=$(printf '%s\n' "$commit_sha" | sed -E \
  's/^(.{8})(.{4}).(.{3}).(.{3})(.{12}).*$/urn:uuid:\1-\2-8\3-a\4-\5/')
if ! printf '%s\n' "$serial_number" | grep -Eq \
  '^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'; then
  echo "不能从提交摘要生成 CycloneDX 序列号" >&2
  exit 1
fi
manifest_sha=$(sha256_file "$manifest")
lock_sha=$(sha256_file "$lockfile")
source_ref=${YANBAO_SOURCE_REF:-${GITHUB_REF:-refs/tags/v$version}}
repository=${GITHUB_REPOSITORY:-YanXuLang/yanbao}
component_ref="pkg:github/YanXuLang/yanbao@$version"
runtime_ref="pkg:github/YanXuLang/yanxu@$minimum_yanxu"

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
          {name: "cdx:yanbao:lock:format", value: $lock_format},
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
mv "$output.tmp" "$output"

jq -e \
  --arg version "$version" \
  --arg minimum_yanxu "$minimum_yanxu" \
  --arg commit "$commit_sha" \
  --arg serial_number "$serial_number" \
  --arg manifest_sha "$manifest_sha" \
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
     select(.name == "cdx:yanbao:lock:sha256" and .value == $lock_sha)] | length) == 1
   and ([.components[] |
     select(.name == "yanxu" and .version == $minimum_yanxu and .scope == "required")] | length) == 1
   and (.dependencies | length) == 2' "$output" >/dev/null

if grep -F "$root" "$output" >/dev/null; then
  echo "SBOM 不得包含构建机绝对路径" >&2
  exit 1
fi
