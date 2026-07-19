# 安全策略

## 支持范围

安全修复优先提供给最新发布版本；公开注册表能力在完成威胁模型和安全门禁前不会标记为稳定。

## 报告漏洞

请不要为未修复的供应链、安全或凭据问题创建公开 Issue。使用 GitHub 仓库的 **Security → Report a vulnerability** 私密报告功能，并提供受影响版本与系统、最小复现、可观察影响和已知缓解方式。

涉及言序核心解析器的漏洞会与`YanXuLang/yanxu`协调修复和披露。言包 0.6.0 要求言序 1.1.17 安全基线；GitHub 简写只展开为 HTTPS Git URL，实际获取、缓存和锁定仍由言序工程协议完成。远程制品中的链接、设备文件、FIFO、越界路径和超限归档会在进入缓存前被拒绝，工程子进程也受权限、分操作超时、UTF-8 与输出大小门禁约束。

依赖审计默认拒绝 critical/high。任何抑制都必须精确指定诊断代码、复核原因和 UTC 到期日；过期项不会继续掩盖发现。项目事务在覆盖前保留恢复信息，并在检测到并发修改或无效日志时拒绝写回。

正式发行档案均配有单 LF 的 SHA-256 文件，并由两套校验工具复验。Release 同时提供六份逐目标 CycloneDX 1.5 SBOM、逐目标构建元数据、构建来源证明和 SBOM 证明；每份签名 SBOM 谓词绑定对应归档摘要、目标和锁文件摘要，构建元数据还绑定源码提交、言序编译器版本及其官方标签提交、清单及独立应用摘要。发布流程在公开前验证证明，公开安装冒烟使用同一批已验签字节，正式化前任何一步失败都会保持预发布；已经稳定发布的 Release 不会被回退或覆盖。安装器只把`YANBAO_GITHUB_TOKEN`的私有副本交给 HTTPS 下载请求，不把该副本留在调用作用域，并在启动本机言序或发行程序前移除`GH_TOKEN`、`GITHUB_TOKEN`、`YANBAO_GITHUB_TOKEN`和`YANXU_GITHUB_TOKEN`。请在公开披露前为修复预留合理时间。

## 验证正式发行

以下示例验证当前最新的 Linux x86-64 制品。需要 GitHub CLI、`jq`和`sha256sum`，并按归档格式安装`tar`或`unzip`；验证其他目标时只需替换`target`，脚本会选择对应归档格式。

```sh
set -eu
repo=YanXuLang/yanbao
tag="$(gh release view --repo "$repo" --json tagName --jq .tagName)"
version="${tag#v}"
target=x86_64-unknown-linux-gnu
case "$target" in
  *windows*) archive="yanbao-$target.zip" ;;
  *) archive="yanbao-$target.tar.gz" ;;
esac
checksum="yanbao-$target.sha256"
metadata="yanbao-$target.build.json"
lockfile="yanbao-$target.lock"
sbom="yanbao-$target.cdx.json"
provenance="yanbao-$version.provenance.jsonl"
sbom_attestation="yanbao-$version.sbom-attestation.jsonl"
workflow="$repo/.github/workflows/release.yml"
directory="$(mktemp -d "${TMPDIR:-/tmp}/yanbao-verify.XXXXXX")"

test "$(gh release view "$tag" --repo "$repo" --json isDraft,isPrerelease \
  --jq '.isDraft == false and .isPrerelease == false')" = true
commit="$(gh api "repos/$repo/commits/$tag" --jq .sha)"
test "${#commit}" -eq 40
gh release download "$tag" --repo "$repo" --dir "$directory"
cd "$directory"
test "$(find . -maxdepth 1 -type f | wc -l)" -eq 32
for file in "$archive" "$checksum" "$metadata" "$lockfile" \
  "$sbom" "$provenance" "$sbom_attestation"; do
  test -s "$file"
done

verify_provenance() {
  subject=$1
  for source_ref in "refs/tags/$tag" refs/heads/main; do
    if gh attestation verify "$subject" --repo "$repo" \
      --signer-workflow "$workflow" --bundle "$provenance" \
      --source-digest "$commit" --source-ref "$source_ref" >/dev/null 2>&1; then
      return 0
    fi
  done
  echo "不能验证 $subject 的构建来源" >&2
  return 1
}

for subject in "$archive" "$checksum" "$metadata" "$lockfile" "$sbom"; do
  verify_provenance "$subject"
done
sha256sum --check "$checksum"

archive_sha="$(sha256sum "$archive" | awk '{print $1}')"
archive_bytes="$(wc -c < "$archive" | tr -d ' ')"
lock_sha="$(sha256sum "$lockfile" | awk '{print $1}')"
yanxu_version="$(jq -er .minimum_yanxu_version "$metadata")"
printf '%s\n' "$yanxu_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
yanxu_ref="refs/tags/v$yanxu_version"
yanxu_commit="$(gh api "repos/YanXuLang/yanxu/commits/v$yanxu_version" --jq .sha)"
printf '%s\n' "$yanxu_commit" | grep -Eq '^[0-9a-f]{40}$'
sbom_verification=
for source_ref in "refs/tags/$tag" refs/heads/main; do
  if candidate="$(gh attestation verify "$archive" --repo "$repo" \
    --signer-workflow "$workflow" --bundle "$sbom_attestation" \
    --predicate-type https://cyclonedx.org/bom \
    --source-digest "$commit" --source-ref "$source_ref" \
    --format json 2>/dev/null)"; then
    sbom_verification="$candidate"
    break
  fi
done
test -n "$sbom_verification"

jq -e --arg version "$version" --arg commit "$commit" \
  --arg ref "refs/tags/$tag" --arg target "$target" \
  --arg archive "$archive" --arg archive_sha "$archive_sha" \
  --arg lock_sha "$lock_sha" --arg yanxu_version "$yanxu_version" \
  --arg yanxu_ref "$yanxu_ref" --arg yanxu_commit "$yanxu_commit" \
  '.schema_version == 1 and .version == $version
   and .source.commit_sha == $commit and .source.ref == $ref
   and .artifact.name == $archive and .artifact.sha256 == $archive_sha
   and .build.target == $target and .build.profile == "release"
   and .build.standalone and (.build.separate_runtime_bundled | not)
   and .build.compiler.version == $yanxu_version
   and .build.compiler.source_ref == $yanxu_ref
   and .build.compiler.commit_sha == $yanxu_commit
   and .build.lock.target == $target and .build.lock.sha256 == $lock_sha' \
  "$metadata" >/dev/null
printf '%s\n' "$sbom_verification" | jq -e --slurpfile sbom "$sbom" \
  --arg commit "$commit" --arg ref "refs/tags/$tag" --arg target "$target" \
  --arg archive "$archive" --arg archive_sha "$archive_sha" \
  --arg archive_bytes "$archive_bytes" --arg lock_sha "$lock_sha" '
    def property($document; $name; $value):
      ([$document.metadata.component.properties[]? |
        select(.name == $name and .value == $value)] | length) == 1;
    length == 1 and ($sbom | length) == 1 and
    (.[0].verificationResult.statement as $statement |
      $statement.predicateType == "https://cyclonedx.org/bom" and
      $statement.predicate.bomFormat == "CycloneDX" and
      $statement.predicate.specVersion == "1.5" and
      ($statement.subject | length) == 1 and
      ([ $statement.subject[] |
        select(.name == $archive and .digest.sha256 == $archive_sha) ] | length) == 1 and
      $statement.predicate == $sbom[0] and
      property($statement.predicate; "cdx:yanbao:source:commit"; $commit) and
      property($statement.predicate; "cdx:yanbao:source:ref"; $ref) and
      property($statement.predicate; "cdx:yanbao:artifact:name"; $archive) and
      property($statement.predicate; "cdx:yanbao:artifact:sha256"; $archive_sha) and
      property($statement.predicate; "cdx:yanbao:artifact:bytes"; $archive_bytes) and
      property($statement.predicate; "cdx:yanbao:build:target"; $target) and
      property($statement.predicate; "cdx:yanbao:lock:target"; $target) and
      property($statement.predicate; "cdx:yanbao:lock:sha256"; $lock_sha))
  ' >/dev/null

case "$archive" in
  *.tar.gz)
    archive_entries="$(tar -tzf "$archive")" || {
      echo "不能读取言包 tar 归档目录" >&2
      exit 1
    }
    ;;
  *.zip)
    archive_entries="$(unzip -Z1 "$archive")" || {
      echo "不能读取言包 zip 归档目录" >&2
      exit 1
    }
    ;;
  *)
    echo "不支持的言包归档格式：$archive" >&2
    exit 1
    ;;
esac
test -n "$archive_entries"
if printf '%s\n' "$archive_entries" |
  sed 's#^\./##; s#/$##; s#.*/##' |
  grep -Eq '^yanxu([.-]|$)'
then
  echo "言包发行档案不得捆绑言序运行时" >&2
  exit 1
fi
```

正式工作流既可由目标标签直接触发，也可在`main`与该标签精确指向同一提交时由自动发布流程调用，因此证明的允许来源 ref 只有示例中的两种；无论哪种路径，提交摘要和签名工作流都必须同时精确匹配。不要只核对文件名、Release 页面或单独的 SHA-256 后便跳过来源证明。
