# 言包路线图

## 0.2.0：纯言序工程工具（开发中）

- [x] 删除 Cargo/Rust 业务实现，命令层完全迁移到言序；
- [x] Unix、PowerShell、CMD 无业务启动器；
- [x] 版本化工程协议握手；
- [x] 格式 2 项目初始化、依赖增删与失败回滚；
- [x] install/update/check/test/run/build/clean；
- [x] 完整传递依赖 `tree/why` 和 `doctor`；
- [x] YXB 与当前平台独立应用构建；
- [x] 真正的 `outdated` 和 `update --dry-run` 更新计划；
- [x] 确定性 `pack`、离线 `vendor`、依赖 `audit` 和结构化 `doc`；
- [x] 工作区批量命令与增量构建缓存报告；
- [ ] 稳定 JSON Schema 和 LSP 工程调用验证。

## 后续

- 测试注册表只读协议、撤回与漏洞元数据；
- 内容寻址归档、来源证明和签名策略；
- 公开写入、登录与发布必须单独完成威胁模型和安全评审。
