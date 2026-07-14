mod manifest;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use manifest::{DependencySpec, MANIFEST_NAME, ManifestEditor, create_manifest};
use serde_json::json;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use yanxu::package::{self, Manifest, ResolvedDependency};

#[derive(Parser)]
#[command(
    name = "yanbao",
    version,
    about = "言包——言序编程语言的官方包管理器",
    long_about = "言包负责创建言序项目、维护依赖并调用言序核心解析器生成可复现锁文件。所有命令均提供中文别名。"
)]
struct Cli {
    /// 清单文件或项目目录；默认从当前目录向上查找。
    #[arg(long, global = true, value_name = "路径")]
    manifest_path: Option<PathBuf>,

    /// 输出稳定的 JSON，供编辑器与 CI 使用。
    #[arg(long, global = true)]
    json: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 创建新的言序项目。
    #[command(visible_alias = "新")]
    Init {
        #[arg(default_value = ".")]
        path: PathBuf,
        #[arg(long)]
        name: Option<String>,
        /// 允许覆盖已有的模板文件。
        #[arg(long)]
        force: bool,
    },

    /// 添加路径、Git 或注册表依赖。
    #[command(visible_alias = "加")]
    Add {
        name: String,
        #[arg(long, value_name = "要求")]
        version: Option<String>,
        #[arg(long, conflicts_with_all = ["git", "registry"])]
        path: Option<PathBuf>,
        #[arg(long, conflicts_with_all = ["path", "registry"])]
        git: Option<String>,
        #[arg(long, requires = "git")]
        rev: Option<String>,
        #[arg(long, conflicts_with_all = ["path", "git"])]
        registry: Option<String>,
        #[arg(long)]
        offline: bool,
        /// 只修改清单，不重新生成锁文件。
        #[arg(long)]
        no_lock: bool,
    },

    /// 移除依赖。
    #[command(visible_alias = "移")]
    Remove {
        name: String,
        #[arg(long)]
        offline: bool,
        #[arg(long)]
        no_lock: bool,
    },

    /// 安装并验证清单中的全部依赖。
    #[command(visible_alias = "装")]
    Install {
        #[arg(long)]
        offline: bool,
    },

    /// 忽略旧锁定并重新解析全部依赖。
    #[command(visible_alias = "更")]
    Update {
        #[arg(long)]
        offline: bool,
    },

    /// 显示项目与直接依赖。
    #[command(name = "list", visible_alias = "列")]
    List,

    /// 安装依赖后调用言序运行项目入口。
    #[command(visible_alias = "行")]
    Run {
        #[arg(long)]
        offline: bool,
    },
}

fn main() -> ExitCode {
    match execute(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("言包有误：{error:#}");
            ExitCode::from(1)
        }
    }
}

fn execute(cli: Cli) -> Result<()> {
    match cli.command {
        Commands::Init { path, name, force } => init(&path, name.as_deref(), force, cli.json),
        Commands::Add {
            name,
            version,
            path,
            git,
            rev,
            registry,
            offline,
            no_lock,
        } => {
            let specification = if let Some(path) = path {
                DependencySpec::Path {
                    path,
                    requirement: version,
                }
            } else if let Some(url) = git {
                DependencySpec::Git {
                    url,
                    revision: rev,
                    requirement: version,
                }
            } else {
                DependencySpec::Registry {
                    requirement: version.unwrap_or_else(|| "*".into()),
                    registry,
                }
            };
            let manifest_path = locate_manifest(cli.manifest_path.as_deref())?;
            mutate_manifest(&manifest_path, offline, no_lock, |editor| {
                editor.add_dependency(&name, specification)
            })?;
            report_change("add", &name, &manifest_path, cli.json)
        }
        Commands::Remove {
            name,
            offline,
            no_lock,
        } => {
            let manifest_path = locate_manifest(cli.manifest_path.as_deref())?;
            mutate_manifest(&manifest_path, offline, no_lock, |editor| {
                editor.remove_dependency(&name)
            })?;
            report_change("remove", &name, &manifest_path, cli.json)
        }
        Commands::Install { offline } => {
            let manifest = load_manifest(cli.manifest_path.as_deref())?;
            let resolved = package::ensure_lock(&manifest, offline)?;
            report_resolution("install", &manifest, &resolved, cli.json)
        }
        Commands::Update { offline } => {
            let manifest = load_manifest(cli.manifest_path.as_deref())?;
            let resolved = package::update_lock(&manifest, offline)?;
            report_resolution("update", &manifest, &resolved, cli.json)
        }
        Commands::List => {
            let manifest = load_manifest(cli.manifest_path.as_deref())?;
            report_manifest(&manifest, cli.json)
        }
        Commands::Run { offline } => {
            let manifest = load_manifest(cli.manifest_path.as_deref())?;
            package::ensure_lock(&manifest, offline)?;
            run_package(&manifest, cli.json)
        }
    }
}

fn init(path: &Path, requested_name: Option<&str>, force: bool, json_output: bool) -> Result<()> {
    fs::create_dir_all(path).with_context(|| format!("不能创建 {}", path.display()))?;
    let name = requested_name
        .map(str::to_owned)
        .or_else(|| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .filter(|name| !name.is_empty() && name != ".")
        .unwrap_or_else(|| "言序项目".into());
    let manifest_path = path.join(MANIFEST_NAME);
    let source_path = path.join("src").join("主.yx");
    for candidate in [&manifest_path, &source_path] {
        if candidate.exists() && !force {
            bail!("{} 已存在；如需覆盖请使用 --force", candidate.display());
        }
    }
    fs::create_dir_all(path.join("src"))?;
    fs::write(&manifest_path, create_manifest(&name)?)?;
    fs::write(&source_path, "言 「你好，言序！」；\n")?;
    let ignore_path = path.join(".gitignore");
    if !ignore_path.exists() {
        fs::write(ignore_path, ".yanxu/\n")?;
    }
    let manifest = package::load(&manifest_path)?;
    package::ensure_lock(&manifest, true)?;
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "schema_version": 1,
                "action": "init",
                "name": manifest.name,
                "version": manifest.version.to_string(),
                "manifest": manifest.path,
            }))?
        );
    } else {
        println!(
            "已创建 {} {}：{}",
            manifest.name,
            manifest.version,
            path.display()
        );
    }
    Ok(())
}

fn locate_manifest(input: Option<&Path>) -> Result<PathBuf> {
    Ok(load_manifest(input)?.path)
}

fn load_manifest(input: Option<&Path>) -> Result<Manifest> {
    let input = input.unwrap_or_else(|| Path::new("."));
    if input.is_file() {
        return package::load(input).map_err(Into::into);
    }
    package::discover(input)?
        .with_context(|| format!("从 {} 起未找到 {MANIFEST_NAME}", input.display()))
}

fn mutate_manifest(
    manifest_path: &Path,
    offline: bool,
    no_lock: bool,
    mutation: impl FnOnce(&mut ManifestEditor) -> Result<()>,
) -> Result<()> {
    let original_manifest = fs::read(manifest_path)?;
    let lock_path = manifest_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(package::LOCK_NAME);
    let original_lock = fs::read(&lock_path).ok();
    let result: Result<()> = (|| {
        let mut editor = ManifestEditor::open(manifest_path)?;
        mutation(&mut editor)?;
        editor.save()?;
        let manifest = package::load(manifest_path)?;
        if !no_lock {
            package::update_lock(&manifest, offline)?;
        }
        Ok(())
    })();
    if let Err(error) = result {
        fs::write(manifest_path, original_manifest).context("回滚清单失败")?;
        match original_lock {
            Some(lock) => fs::write(&lock_path, lock).context("回滚锁文件失败")?,
            None if lock_path.exists() => fs::remove_file(&lock_path).context("清理锁文件失败")?,
            None => {}
        }
        return Err(error).context("变更已回滚");
    }
    Ok(())
}

fn report_change(action: &str, name: &str, manifest_path: &Path, json_output: bool) -> Result<()> {
    let manifest = package::load(manifest_path)?;
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "schema_version": 1,
                "action": action,
                "dependency": name,
                "manifest": manifest.path,
                "dependency_count": manifest.dependencies.len(),
            }))?
        );
    } else {
        let verb = if action == "add" { "添加" } else { "移除" };
        println!(
            "已{verb}依赖“{name}”；现有 {} 项直接依赖",
            manifest.dependencies.len()
        );
    }
    Ok(())
}

fn report_resolution(
    action: &str,
    manifest: &Manifest,
    resolved: &std::collections::BTreeMap<String, ResolvedDependency>,
    json_output: bool,
) -> Result<()> {
    if json_output {
        let packages = resolved
            .values()
            .map(|dependency| {
                json!({
                    "name": dependency.locked.name,
                    "version": dependency.locked.version,
                    "source": dependency.locked.source,
                    "revision": dependency.locked.revision,
                    "checksum": dependency.locked.checksum,
                    "entry": dependency.locked.entry,
                })
            })
            .collect::<Vec<_>>();
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "schema_version": 1,
                "action": action,
                "package": manifest.name,
                "lockfile": manifest.root.join(package::LOCK_NAME),
                "packages": packages,
            }))?
        );
    } else {
        let verb = if action == "update" {
            "更新"
        } else {
            "安装"
        };
        println!(
            "已{verb} {} 项依赖；锁文件：{}",
            resolved.len(),
            manifest.root.join(package::LOCK_NAME).display()
        );
    }
    Ok(())
}

fn report_manifest(manifest: &Manifest, json_output: bool) -> Result<()> {
    if json_output {
        let dependencies = manifest
            .dependencies
            .iter()
            .map(|(name, dependency)| json!({ "name": name, "source": dependency.to_string() }))
            .collect::<Vec<_>>();
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "schema_version": 1,
                "name": manifest.name,
                "version": manifest.version.to_string(),
                "entry": manifest.entry,
                "manifest": manifest.path,
                "dependencies": dependencies,
            }))?
        );
    } else {
        println!(
            "{} {}（入口：{}）",
            manifest.name,
            manifest.version,
            manifest.entry.display()
        );
        if manifest.dependencies.is_empty() {
            println!("无直接依赖");
        } else {
            for (name, dependency) in &manifest.dependencies {
                println!("- {name}: {dependency}");
            }
        }
    }
    Ok(())
}

fn run_package(manifest: &Manifest, json_output: bool) -> Result<()> {
    let binary = env::var_os("YANXU_BIN").unwrap_or_else(|| "yanxu".into());
    if json_output {
        let output = Command::new(&binary)
            .arg("包")
            .arg("运行")
            .arg(&manifest.root)
            .output()
            .with_context(|| format!("不能启动 {:?}；请先安装言序或设置 YANXU_BIN", binary))?;
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "schema_version": 1,
                "action": "run",
                "package": manifest.name,
                "success": output.status.success(),
                "exit_code": output.status.code(),
                "stdout": String::from_utf8_lossy(&output.stdout),
                "stderr": String::from_utf8_lossy(&output.stderr),
            }))?
        );
        if !output.status.success() {
            bail!("言序运行器退出：{}", output.status);
        }
    } else {
        let status = Command::new(&binary)
            .arg("包")
            .arg("运行")
            .arg(&manifest.root)
            .status()
            .with_context(|| format!("不能启动 {:?}；请先安装言序或设置 YANXU_BIN", binary))?;
        if !status.success() {
            bail!("言序运行器退出：{status}");
        }
    }
    Ok(())
}
