# 言包

[![CI](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml/badge.svg)](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-c43b2f)](LICENSE)

言包（`yanbao`）是言序的官方工程与包管理工具。自 0.2.0 起，命令层完全由言序语言编写；仓库不再包含 Cargo 工程或 Rust 业务代码。使用言包之前须先安装言序 1.1.5 或更高版本。

言包负责命令分派、项目工作流、事务回滚、诊断和用户输出；`言序.toml`、`言序.lock`、完整依赖图、模块导出和 YXB 构建全部通过言序的版本化 JSON 工程协议完成。因此，言包不会复制第二套 TOML、语义化版本或依赖选择实现。

## 安装与运行

先安装言序 1.1.5 或更高版本，再克隆本仓库并把仓库目录加入 PATH（启动器与`src/`必须保持在同一分发目录）。Unix 使用`yanbao`，Windows 使用`yanbao.cmd`或`yanbao.ps1`。启动器只负责定位`src/主.yx`和`yanxu`：

```sh
./yanbao --help
YANXU_BIN=/自定义路径/yanxu ./yanbao doctor
yanxu src/主.yx -- doctor
```

不需要 Rust，也不需要先编译言包。言包源码本身就是可执行实现。

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
./yanbao doctor
```

完整职责和安全边界见[架构说明](docs/ARCHITECTURE.md)，进度见[路线图](docs/ROADMAP.md)。
