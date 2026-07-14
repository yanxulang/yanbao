# 言包

[![CI](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml/badge.svg)](https://github.com/YanXuLang/yanbao/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-c43b2f)](LICENSE)

言包（`yanbao`）是专属于[言序语言](https://github.com/YanXuLang/yanxu)的官方包管理器。它负责创建项目、编辑依赖和组织日常工作流；`言序.toml`解析、依赖获取与`言序.lock`生成始终复用`yanxu::package`，不会形成第二套包格式。

## 当前能力

- `init` / `新`：创建清单、锁文件、`src/主.yx`和忽略文件；
- `add` / `加`：添加中央索引、路径或 Git 依赖；
- `remove` / `移`：移除依赖；
- `install` / `装`：安装并校验锁定依赖，支持离线模式；
- `update` / `更`：显式重新解析全部依赖；
- `list` / `列`：显示包和直接依赖；
- `run` / `行`：锁定依赖后调用`yanxu`按清单权限运行入口；
- 全局`--json`：输出`schema_version: 1`的机器结果；
- 事务变更：依赖解析失败时自动恢复清单和锁文件。

当前源码锁定言序核心`v1.1.3`：远程包制品只接受安全路径下的普通文件和目录，并受压缩体积、展开体积、单文件大小及条目数限制。新项目模板也会分别声明外连、TCP 监听与 UDP 绑定权限。

公开注册表、搜索、发布、撤回、审计与签名尚未在 0.1 中开放，详见[路线图](docs/ROADMAP.md)。

## 安装

需要 Rust 稳定版工具链；`run`命令还需要已安装的言序运行器。

```sh
cargo install --git https://github.com/YanXuLang/yanbao.git --locked
yanbao --help
```

本地开发：

```sh
cargo build --locked
cargo test --all-targets --locked
```

## 快速开始

```sh
yanbao init 我的项目
yanbao --manifest-path 我的项目 list

# 路径依赖
yanbao --manifest-path 我的项目 add 共享工具 --path ../共享工具 --version '^1'

# Git 依赖
yanbao --manifest-path 我的项目 add 远程工具 \
  --git https://github.com/example/远程工具.git --rev main

yanbao --manifest-path 我的项目 install
yanbao --manifest-path 我的项目 run
```

默认从当前目录向上查找`言序.toml`，也可用全局`--manifest-path <清单或目录>`明确指定。`add`和`remove`会立即更新锁文件；解析失败时两份文件都会回滚。若只想准备清单，可显式传入`--no-lock`。

离线复现与 CI：

```sh
yanbao install --offline
yanbao install --json > 言包结果.json
```

缓存沿用言序核心的`~/.yanxu/缓存`，可通过`YANXU_CACHE`覆盖。自定义运行器路径可通过`YANXU_BIN`设置。

## 依赖来源

```sh
# 默认注册表；未指定时版本要求为 *
yanbao add 文字工具 --version '^1.2'

# 自定义注册表
yanbao add 文字工具 --version '^1.2' --registry https://packages.example/v1

# 本地路径
yanbao add 共享工具 --path ../共享工具

# Git 修订
yanbao add 共享工具 --git https://github.com/example/共享工具.git --rev v1.2.0
```

`yanbao update`会丢弃旧锁定后重新选择版本；日常恢复项目应使用`yanbao install`，以优先验证现有锁定和缓存。

## 设计边界

言包不解释或执行言序源码，也不独立实现解析算法。职责关系、事务语义和安全边界见[架构说明](docs/ARCHITECTURE.md)。包清单与锁文件格式由言序核心的[格式 1 规范](https://github.com/YanXuLang/yanxu/blob/main/spec/language/v1/formats.md)定义。

## 参与项目

提交改动前请阅读[贡献指南](CONTRIBUTING.md)和[安全策略](SECURITY.md)。言包按[MIT License](LICENSE)开源。
