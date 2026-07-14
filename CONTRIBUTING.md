# 参与言包

感谢你帮助言序建立可靠的包生态。

## 开始之前

- 错误修复、文档和测试可直接提交 Pull Request；
- 包清单、锁文件或注册表协议变化须先创建 Issue 讨论，并同步言序核心规范；
- 发布、凭据、签名和撤回相关设计必须包含威胁模型；
- 一个 Pull Request 只处理一组相关改动。

## 本地开发

需要 Rust 稳定版工具链：

```sh
cargo fmt --check
cargo test --all-targets --locked
cargo clippy --all-targets --locked -- -D warnings
```

集成测试会在临时目录创建言序项目，不访问公开注册表。新增命令应同时覆盖人类输出、`--json`和失败回滚；新增网络行为必须覆盖`--offline`。

## 提交与 PR

提交标题使用简短祈使句。PR 请说明用户问题、行为变化、验证命令、格式/安全影响和关联的核心或文档改动。所有贡献按 MIT 许可证发布，并须遵守[行为准则](CODE_OF_CONDUCT.md)。
