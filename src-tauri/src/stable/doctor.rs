use crate::stable::config::apps_folder;
use anyhow::Result;
use std::path::PathBuf;

struct Check {
    name: String,
    passed: bool,
    message: String,
}

fn run_check(name: &str, cmd: &str, args: &[&str]) -> Check {
    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!("{} {}", cmd, args.join(" ")))
        .output();

    let found = output.map(|o| o.status.success()).unwrap_or(false);
    Check {
        name: name.to_string(),
        passed: found,
        message: if found { "Found".to_string() } else { "Not found".to_string() },
    }
}

pub fn run() -> Result<String> {
    let mut checks = Vec::new();

    let homebrew = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("which brew")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    checks.push(Check {
        name: "Homebrew".to_string(),
        passed: homebrew,
        message: if homebrew {
            "Found".to_string()
        } else {
            "Not found".to_string()
        },
    });

    let caddy = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("which caddy")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    checks.push(Check {
        name: "Caddy".to_string(),
        passed: caddy,
        message: if caddy {
            "Found".to_string()
        } else {
            "Not found".to_string()
        },
    });

    let mkcert = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("which mkcert")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    checks.push(Check {
        name: "mkcert".to_string(),
        passed: mkcert,
        message: if mkcert {
            "Found".to_string()
        } else {
            "Not found".to_string()
        },
    });

    let rvm = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("which rvm")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    checks.push(Check {
        name: "RVM".to_string(),
        passed: rvm,
        message: if rvm {
            "Found".to_string()
        } else {
            "Not found".to_string()
        },
    });

    let caddy_running = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("pgrep -x caddy")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    checks.push(Check {
        name: "Caddy running".to_string(),
        passed: caddy_running,
        message: if caddy_running {
            "Running".to_string()
        } else {
            "Not running".to_string()
        },
    });

    let certs_folder = PathBuf::from("/Users/dannysimfukwe/StableCaddy/certs");
    let certs_exists = certs_folder.exists();
    checks.push(Check {
        name: "Certificates directory".to_string(),
        passed: certs_exists,
        message: if certs_exists {
            certs_folder.display().to_string()
        } else {
            "Not found".to_string()
        },
    });

    let projects_folder = apps_folder();
    let projects_exists = projects_folder.exists();
    checks.push(Check {
        name: "Projects directory".to_string(),
        passed: projects_exists,
        message: if projects_exists {
            projects_folder.display().to_string()
        } else {
            "Not found".to_string()
        },
    });

    let mut report = String::from("Running Stable health checks...\n\n");
    for check in &checks {
        let status = if check.passed { "✔" } else { "✖" };
        report.push_str(&format!(
            "{} {}\n    {}\n",
            status, check.name, check.message
        ));
    }

    let all_passed = checks.iter().all(|c| c.passed);
    report.push_str(if all_passed {
        "\nAll checks passed."
    } else {
        "\nSome checks failed."
    });

    Ok(report)
}
