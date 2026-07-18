#!/bin/sh
set -eu

REPOSITORY="${YANBAO_REPOSITORY:-YanXuLang/yanbao}"
VERSION="${YANBAO_VERSION:-latest}"
INSTALL_DIR="${YANBAO_INSTALL_DIR:-$HOME/.local/bin}"
ASSET_DIR="${YANBAO_ASSET_DIR:-}"

say() { printf '%s\n' "$*"; }
fail() { say "言包安装失败：$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "需要命令 $1"; }
download() {
  if [ -n "${YANBAO_GITHUB_TOKEN:-}" ]; then
    curl --disable --fail --location --silent --show-error \
      --proto '=https' --tlsv1.2 \
      --header "Authorization: Bearer ${YANBAO_GITHUB_TOKEN}" "$@"
  else
    curl --disable --fail --location --silent --show-error \
      --proto '=https' --tlsv1.2 "$@"
  fi
}

need tar
need install
if [ -z "$ASSET_DIR" ]; then
  need curl
fi
YANXU_BIN="${YANXU_BIN:-yanxu}"
command -v "$YANXU_BIN" >/dev/null 2>&1 || fail "需要先安装言序 1.1.17 或更高版本（yanxu），也可通过 YANXU_BIN 指定其路径"
export YANXU_BIN
yanxu_version_json="$("$YANXU_BIN" version --json 2>/dev/null)" || fail "无法读取本机言序版本"
yanxu_version="$(printf '%s\n' "$yanxu_version_json" | sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$yanxu_version" ] || fail "本机言序版本报告无效"
yanxu_without_build="${yanxu_version%%+*}"
yanxu_core="${yanxu_without_build%%-*}"
old_ifs="$IFS"
IFS=.
set -- $yanxu_core
IFS="$old_ifs"
[ "$#" -eq 3 ] || fail "本机言序版本报告无效：$yanxu_version"
yanxu_major="$1"; yanxu_minor="$2"; yanxu_patch="$3"
case "$yanxu_major.$yanxu_minor.$yanxu_patch" in
  *[!0-9.]*) fail "本机言序版本报告无效：$yanxu_version" ;;
esac
yanxu_compatible=false
if [ "$yanxu_major" -gt 1 ] ||
   { [ "$yanxu_major" -eq 1 ] && [ "$yanxu_minor" -gt 1 ]; } ||
   { [ "$yanxu_major" -eq 1 ] && [ "$yanxu_minor" -eq 1 ] && [ "$yanxu_patch" -gt 17 ]; } ||
   { [ "$yanxu_major" -eq 1 ] && [ "$yanxu_minor" -eq 1 ] && [ "$yanxu_patch" -eq 17 ] && [ "${yanxu_without_build#*-}" = "$yanxu_without_build" ]; }
then
  yanxu_compatible=true
fi
[ "$yanxu_compatible" = true ] || fail "需要言序 1.1.17 或更高版本，当前为 $yanxu_version"

case "$(uname -s)" in
  Darwin) system="apple-darwin" ;;
  Linux) system="unknown-linux-gnu" ;;
  *) fail "此脚本支持 macOS 与 Linux；Windows 请使用 install.ps1" ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch="x86_64" ;;
  arm64|aarch64) arch="aarch64" ;;
  *) fail "暂不支持处理器架构 $(uname -m)" ;;
esac

target="${arch}-${system}"
asset="yanbao-${target}.tar.gz"
checksum_asset="yanbao-${target}.sha256"
if [ -n "$ASSET_DIR" ] && [ "$VERSION" = "latest" ]; then
  fail "使用 YANBAO_ASSET_DIR 时必须通过 YANBAO_VERSION 指定版本"
elif [ "$VERSION" = "latest" ]; then
  release_json="$(download \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPOSITORY}/releases/latest")" || fail "无法查询最新发行版"
  tag="$(printf '%s' "$release_json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$tag" ] || fail "仓库尚未发布可安装版本"
  version_label="最新版 ${tag}"
else
  case "$VERSION" in v*) tag="$VERSION" ;; *) tag="v$VERSION" ;; esac
  version_label="$tag"
fi
base_url="https://github.com/${REPOSITORY}/releases/download/${tag}"
release_version="${tag#v}"
if [ -n "$ASSET_DIR" ]; then
  case "$ASSET_DIR" in /*) ;; *) fail "YANBAO_ASSET_DIR 必须是绝对路径" ;; esac
  [ -d "$ASSET_DIR" ] || fail "YANBAO_ASSET_DIR 不是目录"
  need cp
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t yanbao)"
stage_launcher=""
stage_app=""
cleanup() {
  rm -rf "$tmp_dir"
  [ -z "$stage_launcher" ] || rm -f "$stage_launcher"
  [ -z "$stage_app" ] || rm -f "$stage_app"
}
trap cleanup EXIT HUP INT TERM

say "正在安装言包 ${version_label}（${target}）…"
if [ -n "$ASSET_DIR" ]; then
  [ -f "$ASSET_DIR/$asset" ] && [ -r "$ASSET_DIR/$asset" ] ||
    fail "本地制品目录缺少可读的 $asset"
  [ -f "$ASSET_DIR/$checksum_asset" ] && [ -r "$ASSET_DIR/$checksum_asset" ] ||
    fail "本地制品目录缺少可读的 $checksum_asset"
  cp "$ASSET_DIR/$asset" "$tmp_dir/$asset" ||
    fail "不能暂存本地发行包"
  cp "$ASSET_DIR/$checksum_asset" "$tmp_dir/$checksum_asset" ||
    fail "不能暂存本地校验文件"
else
  download --output "$tmp_dir/$asset" "$base_url/$asset" ||
    fail "未找到适用于 ${target} 的发行包"
  download --output "$tmp_dir/$checksum_asset" "$base_url/$checksum_asset" ||
    fail "发行包缺少 SHA-256 校验文件"
fi

expected="$(awk '{print $1; exit}' "$tmp_dir/$checksum_asset")"
case "$expected" in ''|*[!0-9A-Fa-f]*) fail "SHA-256 校验文件格式无效" ;; esac
[ "${#expected}" -eq 64 ] || fail "SHA-256 校验文件格式无效"
expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$tmp_dir/$asset" | awk '{print $1}')"
else
  fail "系统没有 sha256sum 或 shasum，无法校验下载"
fi
[ "$expected" = "$actual" ] || fail "SHA-256 校验不一致"
unset YANBAO_GITHUB_TOKEN YANBAO_ASSET_DIR

expanded="$tmp_dir/expanded"
mkdir -p "$expanded"
tar -xzf "$tmp_dir/$asset" -C "$expanded"
for required in yanbao yanbao-app; do
  [ -f "$expanded/$required" ] || fail "发行包缺少 $required"
done
chmod 755 "$expanded/yanbao" "$expanded/yanbao-app"

version_output="$("$expanded/yanbao" --version 2>&1)" || fail "发行包不能使用本机言序运行：$version_output"
printf '%s\n' "$version_output" | grep -Fqx "言包 $release_version" || fail "发行包版本不是言包 $release_version"

mkdir -p "$INSTALL_DIR"
stage_launcher="$(mktemp "$INSTALL_DIR/.yanbao-launcher.XXXXXX")" || fail "不能创建安装临时文件"
stage_app="$(mktemp "$INSTALL_DIR/.yanbao-app.XXXXXX")" || fail "不能创建安装临时文件"
install -m 755 "$expanded/yanbao" "$stage_launcher"
install -m 755 "$expanded/yanbao-app" "$stage_app"
mv -f "$stage_app" "$INSTALL_DIR/yanbao-app"; stage_app=""
mv -f "$stage_launcher" "$INSTALL_DIR/yanbao"; stage_launcher=""

installed_version="$("$INSTALL_DIR/yanbao" --version 2>&1)" || fail "安装后验证失败：$installed_version"
say "言包已安装到 $INSTALL_DIR/yanbao"
say "已验证：$(printf '%s' "$installed_version" | tr '\n' ' ')"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) say "现在可以运行 yanbao。" ;;
  *)
    say "请把以下一行加入你的 shell 配置，然后重开终端："
    say "  export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
esac
