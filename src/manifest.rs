use anyhow::{Context, Result, bail};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tempfile::NamedTempFile;
use toml_edit::{DocumentMut, InlineTable, Item, Table, Value};

pub const MANIFEST_NAME: &str = "言序.toml";

#[derive(Debug, Clone)]
pub enum DependencySpec {
    Registry {
        requirement: String,
        registry: Option<String>,
    },
    Path {
        path: PathBuf,
        requirement: Option<String>,
    },
    Git {
        url: String,
        revision: Option<String>,
        requirement: Option<String>,
    },
}

pub struct ManifestEditor {
    path: PathBuf,
    document: DocumentMut,
}

impl ManifestEditor {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        let source =
            fs::read_to_string(&path).with_context(|| format!("不能读取 {}", path.display()))?;
        let normalized = normalize_manifest(&source);
        let document = normalized
            .parse::<DocumentMut>()
            .with_context(|| format!("不能编辑 {}：清单不是有效格式", path.display()))?;
        Ok(Self { path, document })
    }

    pub fn add_dependency(&mut self, name: &str, specification: DependencySpec) -> Result<()> {
        validate_package_name(name)?;
        let dependencies = dependency_table_mut(&mut self.document)?;
        if dependencies.contains_key(name) {
            bail!("依赖“{name}”已经存在；请先移除或直接编辑清单");
        }

        let mut source = InlineTable::new();
        match specification {
            DependencySpec::Registry {
                requirement,
                registry,
            } => {
                source.insert("版", Value::from(requirement));
                if let Some(registry) = registry {
                    source.insert("源", Value::from(registry));
                }
            }
            DependencySpec::Path { path, requirement } => {
                source.insert("路径", Value::from(path.to_string_lossy().into_owned()));
                if let Some(requirement) = requirement {
                    source.insert("版", Value::from(requirement));
                }
            }
            DependencySpec::Git {
                url,
                revision,
                requirement,
            } => {
                source.insert("git", Value::from(url));
                if let Some(revision) = revision {
                    source.insert("修订", Value::from(revision));
                }
                if let Some(requirement) = requirement {
                    source.insert("版", Value::from(requirement));
                }
            }
        }
        dependencies.insert(name, Item::Value(Value::InlineTable(source)));
        Ok(())
    }

    pub fn remove_dependency(&mut self, name: &str) -> Result<()> {
        let section = dependency_section(&self.document)
            .unwrap_or("依赖")
            .to_owned();
        let Some(dependencies) = self.document.get_mut(&section).and_then(Item::as_table_mut)
        else {
            bail!("清单没有依赖“{name}”");
        };
        if dependencies.remove(name).is_none() {
            bail!("清单没有依赖“{name}”");
        }
        Ok(())
    }

    pub fn save(&self) -> Result<()> {
        let parent = self.path.parent().unwrap_or_else(|| Path::new("."));
        let mut temporary = NamedTempFile::new_in(parent)
            .with_context(|| format!("不能在 {} 创建临时清单", parent.display()))?;
        temporary
            .write_all(render_for_yanxu(&self.document.to_string()).as_bytes())
            .context("不能写入临时清单")?;
        temporary.flush().context("不能刷新临时清单")?;
        temporary
            .persist(&self.path)
            .map_err(|error| error.error)
            .with_context(|| format!("不能替换 {}", self.path.display()))?;
        Ok(())
    }
}

pub fn create_manifest(name: &str) -> Result<String> {
    validate_package_name(name)?;
    Ok(format!(
        "[包]\n格式 = 1\n名 = {name:?}\n版 = \"0.1.0\"\n入口 = \"src/主.yx\"\n\n[依赖]\n\n[权限]\n文件 = [\"src\"]\n网络 = []\n环境 = []\n进程 = false\n"
    ))
}

pub fn validate_package_name(name: &str) -> Result<()> {
    if name.is_empty()
        || name.starts_with(['.', '-'])
        || name
            .chars()
            .any(|character| !(character.is_alphanumeric() || matches!(character, '_' | '-' | '.')))
    {
        bail!("包名“{name}”不规范；仅可用文字、数字、_、-、.");
    }
    Ok(())
}

fn dependency_table_mut(document: &mut DocumentMut) -> Result<&mut Table> {
    let section = dependency_section(document).unwrap_or("依赖").to_owned();
    if document.get(&section).is_none() {
        document.insert(&section, Item::Table(Table::new()));
    }
    document
        .get_mut(&section)
        .and_then(Item::as_table_mut)
        .with_context(|| format!("【{section}】必须是表"))
}

fn dependency_section(document: &DocumentMut) -> Option<&str> {
    if document.get("依赖").is_some() {
        Some("依赖")
    } else if document.get("dependencies").is_some() {
        Some("dependencies")
    } else {
        None
    }
}

/// 将言序允许的中文裸键转换为标准 TOML 引号键，行数保持不变。
fn normalize_manifest(text: &str) -> String {
    text.lines()
        .map(|line| {
            let indentation = &line[..line.len() - line.trim_start().len()];
            let trimmed = line.trim_start();
            if trimmed.starts_with('[') && trimmed.ends_with(']') && !trimmed.starts_with("[[") {
                let section = &trimmed[1..trimmed.len() - 1];
                if !section.is_ascii() {
                    return format!("{indentation}[\"{section}\"]");
                }
            }
            let mut normalized = line.to_owned();
            if let Some(equal) = trimmed.find('=') {
                let key = trimmed[..equal].trim();
                if !key.starts_with(['\'', '"']) && !key.is_ascii() {
                    let absolute = indentation.len();
                    normalized.replace_range(
                        absolute..absolute + trimmed[..equal].trim_end().len(),
                        &format!("\"{key}\""),
                    );
                }
            }
            for key in ["路径", "版", "修订", "源"] {
                normalized = normalized.replace(&format!("{key} ="), &format!("\"{key}\" ="));
                normalized = normalized.replace(&format!("{key}="), &format!("\"{key}\"="));
            }
            normalized
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// 言序 1.0 的兼容解析器会自行给中文表名和四个来源键加引号；写回时
/// 恢复这些裸键，避免旧解析器对已经加引号的键再次加引号。
fn render_for_yanxu(text: &str) -> String {
    text.lines()
        .map(|line| {
            let indentation = &line[..line.len() - line.trim_start().len()];
            let trimmed = line.trim_start();
            let mut rendered = if trimmed.starts_with("[\"") && trimmed.ends_with("\"]") {
                let section = &trimmed[2..trimmed.len() - 2];
                if !section.is_ascii() {
                    format!("{indentation}[{section}]")
                } else {
                    line.to_owned()
                }
            } else {
                line.to_owned()
            };
            for key in ["路径", "版", "修订", "源"] {
                rendered = rendered.replace(&format!("\"{key}\" ="), &format!("{key} ="));
                rendered = rendered.replace(&format!("\"{key}\"="), &format!("{key}="));
            }
            rendered
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edits_chinese_bare_key_manifest() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(MANIFEST_NAME);
        fs::write(&path, create_manifest("示例").unwrap()).unwrap();

        let mut editor = ManifestEditor::open(&path).unwrap();
        editor
            .add_dependency(
                "工具",
                DependencySpec::Path {
                    path: PathBuf::from("../工具"),
                    requirement: Some("^1.0".into()),
                },
            )
            .unwrap();
        editor.save().unwrap();

        let manifest = yanxu::package::load(&path).unwrap();
        assert!(manifest.dependencies.contains_key("工具"));
    }

    #[test]
    fn rejects_unsafe_package_name() {
        assert!(validate_package_name("../越界").is_err());
        assert!(validate_package_name("正常.工具-1").is_ok());
    }
}
