# 言包

[![CI](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml/badge.svg)](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-c43b2f)](LICENSE)

言包（`yanbao`）是言序的官方工程与包管理工具。自 0.2.0 起，命令层完全由言序语言编写；仓库不包含 Cargo 工程或 Rust 业务代码。安装正式 Release 时无需预先安装言序：发行包包含由言序源码编译的 standalone 和仅供工程子命令使用的专用言序运行时；只有从源码参与开发时才需要言序 1.1.6 或更高版本。

言包负责命令分派、项目工作流、事务回滚、诊断和用户输出；`言序.toml`、`言序.lock`、完整依赖图、模块导出和 YXB 构建全部通过言序的版本化 JSON 工程协议完成。因此，言包不会复制第二套 TOML、语义化版本或依赖选择实现。

## 安装

正式发行包由上游`v1.1.6`同一稳定提交的言序 1.1.6 编译，包含当前平台的`yanbao`独立应用和专用言序 1.1.6 工程运行时；不会覆盖系统中已有的`yanxu`，也不把任何包管理业务改写为 Rust。

macOS / Linux：

```sh
curl -fsSL https://raw.githubusercontent.com/YanXuLang/yanbao/main/scripts/install.sh | sh
```

Windows PowerShell：

```powershell
irm https://raw.githubusercontent.com/YanXuLang/yanbao/main/scripts/install.ps1 | iex
```

安装器按操作系统与 x86-64/ARM64 选择制品，强制验证独立 SHA-256 文件，再运行`yanbao --version`确认言包 0.2.1 与言序 1.1.6。可分别用`YANBAO_INSTALL_DIR`、`YANBAO_VERSION`和`YANBAO_GITHUB_TOKEN`覆盖安装目录、版本和 GitHub API 凭据。

## 源码运行

参与开发时先安装言序 1.1.6 或更高版本，再克隆本仓库。Unix 使用`yanbao`，Windows 使用`yanbao.cmd`或`yanbao.ps1`：

```sh
./yanbao --help
./yanbao --version
YANXU_BIN=/自定义路径/yanxu ./yanbao doctor
yanxu src/主.yx -- doctor
```

不需要 Rust。仓库启动器执行源码；Release 启动器会自动识别同目录的已编译应用与专用运行时。

## 主要命令

```sh
yanbao 新 我的项目 --name 示例
yanbao 加 共享工具 --path ../共享工具 --package 共享工具
yanbao 装 --offline
yanbao 树
yanbao 因 共享工具
yanbao 查
yanbao 试
yanbao 行 -- --once
yanbao 构 --release
yanbao 构 --release --standalone
yanbao 清
yanbao 诊
```

英文别名分别为 `init/add/remove/install/update/tree/why/check/test/run/build/clean/doctor`。使用 `--manifest-path <目录>`指定项目；`add/remove`在重新解析失败时恢复清单和锁文件；`--no-lock`可只编辑清单。

`outdated`与`update --dry-run`只生成更新计划而不改写锁文件；`pack`生成固定时间戳、顺序和元数据的 `.yxp`；`vendor`复制完整锁定图供脱离原始依赖位置恢复；`audit`复核校验和、来源、许可证、重复版本和原生制品。

## 开发验证

```sh
yanxu check src/主.yx
yanxu test tests
compile_source="$(mktemp -d)"
cp src/*.yx "$compile_source/"
yanxu compile "$compile_source/主.yx" -o build/yanbao --release --standalone
rm -rf "$compile_source"
./yanbao doctor
```

发布构建必须先把入口和同级模块复制到清单目录之外再编译。这样言序会把它作为需要宿主文件权限的 CLI，而不是只允许访问仓库目录的普通沙箱应用；言包才能管理用户通过参数明确指定的工程路径。

完整职责和安全边界见[架构说明](docs/ARCHITECTURE.md)，进度见[路线图](docs/ROADMAP.md)。
