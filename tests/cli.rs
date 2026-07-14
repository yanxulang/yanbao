use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;

#[test]
fn initializes_and_lists_a_project() {
    let workspace = tempfile::tempdir().unwrap();
    let project = workspace.path().join("问候");

    Command::cargo_bin("yanbao")
        .unwrap()
        .args(["init", project.to_str().unwrap()])
        .assert()
        .success()
        .stdout(predicate::str::contains("已创建 问候 0.1.0"));

    Command::cargo_bin("yanbao")
        .unwrap()
        .args([
            "--manifest-path",
            project.to_str().unwrap(),
            "list",
            "--json",
        ])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"name\": \"问候\""));

    assert!(project.join("言序.toml").is_file());
    assert!(project.join("言序.lock").is_file());
    assert!(project.join("src/主.yx").is_file());
}

#[test]
fn adds_and_removes_a_path_dependency_with_locking() {
    let workspace = tempfile::tempdir().unwrap();
    let app = workspace.path().join("应用");
    let dependency = workspace.path().join("工具");

    for path in [&app, &dependency] {
        Command::cargo_bin("yanbao")
            .unwrap()
            .args(["init", path.to_str().unwrap()])
            .assert()
            .success();
    }

    Command::cargo_bin("yanbao")
        .unwrap()
        .env("YANXU_CACHE", workspace.path().join("缓存"))
        .args([
            "--manifest-path",
            app.to_str().unwrap(),
            "add",
            "工具",
            "--path",
            dependency.to_str().unwrap(),
        ])
        .assert()
        .success();

    let lock = fs::read_to_string(app.join("言序.lock")).unwrap();
    assert!(lock.contains("name = \"工具\""));

    Command::cargo_bin("yanbao")
        .unwrap()
        .args(["--manifest-path", app.to_str().unwrap(), "remove", "工具"])
        .assert()
        .success();

    let lock = fs::read_to_string(app.join("言序.lock")).unwrap();
    assert!(!lock.contains("name = \"工具\""));
}

#[test]
fn rolls_back_manifest_when_dependency_resolution_fails() {
    let workspace = tempfile::tempdir().unwrap();
    let app = workspace.path().join("应用");
    Command::cargo_bin("yanbao")
        .unwrap()
        .args(["init", app.to_str().unwrap()])
        .assert()
        .success();
    let before = fs::read(app.join("言序.toml")).unwrap();

    Command::cargo_bin("yanbao")
        .unwrap()
        .args([
            "--manifest-path",
            app.to_str().unwrap(),
            "add",
            "不存在",
            "--path",
            workspace.path().join("缺失").to_str().unwrap(),
        ])
        .assert()
        .failure()
        .stderr(predicate::str::contains("变更已回滚"));

    assert_eq!(fs::read(app.join("言序.toml")).unwrap(), before);
}

#[cfg(unix)]
#[test]
fn forwards_arguments_after_separator_to_package_entry() {
    use std::os::unix::fs::PermissionsExt;

    let workspace = tempfile::tempdir().unwrap();
    let app = workspace.path().join("应用");
    Command::cargo_bin("yanbao")
        .unwrap()
        .args(["init", app.to_str().unwrap()])
        .assert()
        .success();

    let runner = workspace.path().join("yanxu-test-runner");
    let capture = workspace.path().join("arguments.txt");
    fs::write(
        &runner,
        "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$YANBAO_TEST_CAPTURE\"\n",
    )
    .unwrap();
    let mut permissions = fs::metadata(&runner).unwrap().permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&runner, permissions).unwrap();

    Command::cargo_bin("yanbao")
        .unwrap()
        .env("YANXU_BIN", &runner)
        .env("YANBAO_TEST_CAPTURE", &capture)
        .args([
            "--manifest-path",
            app.to_str().unwrap(),
            "run",
            "--",
            "--once",
            "article-1",
        ])
        .assert()
        .success();

    let arguments = fs::read_to_string(capture).unwrap();
    assert!(arguments.starts_with("包\n运行\n"));
    assert!(arguments.ends_with("--\n--once\narticle-1\n"));
}
