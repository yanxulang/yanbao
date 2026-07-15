# 参与言包

言包 0.2 的业务实现必须使用言序语言。不得重新加入 Cargo 工程、Rust 命令分派器或另一套清单/锁解析器。

## 本地验证

需要言序 1.1.5 或更高版本：

```sh
yanxu version --json
yanxu check src/主.yx
yanxu test tests
YANXU_BIN=yanxu ./yanbao doctor
YANXU_BIN=yanxu ./yanbao --version
compile_source="$(mktemp -d)"
cp src/*.yx "$compile_source/"
yanxu compile "$compile_source/主.yx" -o build/yanbao --release --standalone
rm -rf "$compile_source"
```

新增命令应覆盖中文/英文名称、成功输出、非零失败、事务恢复及三平台启动器。包语义变化必须先进入言序核心和工程协议，再由言包编排；网络、注册表、原生制品或发布能力须附威胁模型。

PR 请说明用户问题、行为变化、验证命令、协议版本和安全影响。所有贡献按 MIT 许可证发布并遵守[行为准则](CODE_OF_CONDUCT.md)。
