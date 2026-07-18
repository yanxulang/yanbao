# 言包

[![CI](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml/badge.svg)](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-c43b2f)](LICENSE)

言包（`yanbao`）是言序的官方工程与包管理工具。自 0.2.0 起，命令层完全由言序语言编写；仓库不包含 Cargo 工程或 Rust 业务代码。言包依赖本机安装的言序 1.1.17 或更高版本，正式 Release 只包含由言序源码编译的 standalone，不再捆绑另一份运行时。

言包负责命令分派、项目工作流、事务回滚、诊断和用户输出；`言序.toml`、`言序.lock`、完整依赖图、模块导出和 YXB 构建全部通过言序的版本化 JSON 工程协议完成。因此，言包不会复制第二套 TOML、语义化版本或依赖选择实现。

## 安装

请先安装言序 1.1.17 或更高版本，并确保`yanxu`在`PATH`中（也可设置`YANXU_BIN`）。安装器会在下载前检查本机言序；缺失或不兼容时立即终止。正式发行包只安装当前平台的`yanbao`独立应用，不会复制或覆盖言序运行时。

macOS / Linux：

```sh
curl -fsSL https://get.yanxu.dev/yanbao | sh
```

Windows PowerShell：

```powershell
irm https://get.yanxu.dev/yanbao/windows | iex
```

安装器按操作系统与 x86-64/ARM64 选择制品，强制验证独立 SHA-256 文件，再用本机言序运行`yanbao --version`确认兼容性。可分别用`YANXU_BIN`、`YANBAO_INSTALL_DIR`、`YANBAO_VERSION`和`YANBAO_GITHUB_TOKEN`覆盖言序路径、安装目录、版本和 GitHub API 凭据。

## 源码运行

参与开发时先安装言序 1.1.17 或更高版本，再克隆本仓库。Unix 使用`yanbao`，Windows 使用`yanbao.cmd`或`yanbao.ps1`：

```sh
./yanbao --help
./yanbao --version
YANXU_BIN=/自定义路径/yanxu ./yanbao doctor
yanxu src/主.yx -- doctor
```

不需要 Rust。仓库启动器执行源码；Release 启动器会自动识别同目录的已编译应用，两者都调用本机言序提供工程协议。

## 主要命令

```sh
yanbao 新 我的项目 --name 示例
yanbao 加 json
yanbao 加 yanxu-json
yanbao 加 other-org/yanxu-json
yanbao 新 我的窗口 --name 示例窗口 --gui
yanbao 加 共享工具 --path ../共享工具 --package 共享工具
yanbao 装 --offline
yanbao 树
yanbao 因 共享工具
yanbao 查
yanbao 试
yanbao 行 -- --once
yanbao 构 --release
yanbao 构 --release --standalone
yanbao 构 --release --bundle
yanbao 应用包
yanbao 清
yanbao 诊
```

英文别名分别为 `new/init/add/remove/install/update/tree/why/check/test/run/build/bundle/clean/doctor`。`new`与`init`等价；`add`默认从 GitHub 取包：`json`和`yanxu-json`都解析为`yanxulang/yanxu-json`，`other-org/yanxu-json`则直接使用指定组织和仓库。本地别名会省略`yanxu-`前缀；`--package`可覆盖仓库内的实际包名。显式`--git`、`--path`和`--registry`仍可用于自定义来源。

命令行会在访问工程前严格检查未知选项、缺少的选项值、多余位置参数和互斥选项，并以稳定诊断代码和用法提示失败。`yanbao help <命令>`或`yanbao <命令> --help`可查看子命令选项；只有`run`接受`--`后的原样程序参数。

使用 `--manifest-path <目录>`指定项目；`add/remove`在重新解析失败时恢复清单和锁文件；`--no-lock`可只编辑清单。

`new/init`先在目标的同一文件系统内生成、解析并检查完整项目，再提交到目标；`--force`只替换清单、入口、锁文件和言包新建的忽略文件，不删除其他内容。`add/remove`在修改真实清单前通过核心工程协议预演编辑，并持久记录原清单、原锁文件、期望清单和解析阶段。普通失败会立即回滚；若进程中断后检测到恢复日志，确认没有其他进程后对原命令加`--recover`（或`--恢复`）。恢复只接受原文或日志记录的事务内容；检测到并发修改时以`TXN005`拒绝覆盖。

所有会启动言序子进程的命令都接受`--timeout <毫秒>`（中文别名`--超时`），也可设置`YANBAO_TIMEOUT`；命令行值优先于环境变量，合法范围为 1 至 86400000 毫秒。默认值按工作负载区分：元数据操作 1 分钟，检查与文档 5 分钟，解析、更新及网络审计 10 分钟，测试、打包与辖制 15 分钟，构建与 Bundle 30 分钟，`run`最多运行 24 小时。超时由言序运行时终止并回收子进程。

所有命令支持`--message-format human|json|json-lines`（中文别名`--消息格式`）。`json`只在标准输出写一个最终结果；`json-lines`逐行写消息、诊断、变更和制品事件，并以结果事件结束。结果包含 Schema 版本、命令、成功状态、退出码、项目根、阶段、诊断、变更、制品和耗时；失败仍以非零进程状态退出，运行时踪迹写入标准错误。正式格式见[`schemas/yanbao-cli-output-v1.json`](schemas/yanbao-cli-output-v1.json)。

`new --gui`（或`init --gui`）会加入官方 `yanxu-gui`（言窗）依赖、图形权限、应用标识与窗口配置；
`build --bundle` 生成 macOS `.app`、Windows GUI 应用目录或 Linux AppDir。开发官方
多仓工作区时可用 `--gui-path /路径/yanxu-gui` 锁定本地言窗包，普通用户无需此选项。

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
