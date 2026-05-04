use crate::stable::config::apps_folder;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Serialize, Deserialize)]
pub struct DependencyStatus {
    pub name: String,
    pub installed: bool,
    pub version: Option<String>,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct DependenciesStatus {
    pub homebrew: DependencyStatus,
    pub caddy: DependencyStatus,
    pub mkcert: DependencyStatus,
    pub ruby: DependencyStatus,
}

fn check_command_exists(cmd: &str) -> (bool, Option<String>) {
    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!("which {}", cmd))
        .output();

    match output {
        Ok(o) if o.status.success() => {
            let path = String::from_utf8_lossy(&o.stdout).trim().to_string();
            (true, Some(path))
        }
        _ => (false, None),
    }
}

fn get_homebrew_status() -> DependencyStatus {
    let (found, path) = check_command_exists("brew");
    if found {
        let version = std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg("brew --version")
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string());

        DependencyStatus {
            name: "Homebrew".to_string(),
            installed: true,
            version,
            message: path.unwrap_or_default(),
        }
    } else {
        DependencyStatus {
            name: "Homebrew".to_string(),
            installed: false,
            version: None,
            message: "Not found - install from brew.sh".to_string(),
        }
    }
}

fn get_caddy_status() -> DependencyStatus {
    let (found, path) = check_command_exists("caddy");
    if found {
        let version = std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg("caddy version")
            .output()
            .ok()
            .and_then(|o| {
                let v = String::from_utf8_lossy(&o.stdout).trim().to_string();
                Some(v.lines().next().unwrap_or(&v).to_string())
            });

        DependencyStatus {
            name: "Caddy".to_string(),
            installed: true,
            version,
            message: path.unwrap_or_default(),
        }
    } else {
        DependencyStatus {
            name: "Caddy".to_string(),
            installed: false,
            version: None,
            message: "Not found".to_string(),
        }
    }
}

fn get_mkcert_status() -> DependencyStatus {
    let (found, path) = check_command_exists("mkcert");
    if found {
        let version = std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg("mkcert --version")
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string());

        DependencyStatus {
            name: "mkcert".to_string(),
            installed: true,
            version,
            message: path.unwrap_or_default(),
        }
    } else {
        DependencyStatus {
            name: "mkcert".to_string(),
            installed: false,
            version: None,
            message: "Not found".to_string(),
        }
    }
}

fn get_ruby_status() -> DependencyStatus {
    let rvm = check_command_exists("rvm").0;
    let rbenv = check_command_exists("rbenv").0;
    let ruby = check_command_exists("ruby").0;

    if rvm || rbenv || ruby {
        let version = std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg("ruby --version")
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string());

        let manager = if rvm { "RVM" } else if rbenv { "rbenv" } else { "system" };
        DependencyStatus {
            name: "Ruby".to_string(),
            installed: true,
            version,
            message: format!("Found via {}", manager),
        }
    } else {
        DependencyStatus {
            name: "Ruby".to_string(),
            installed: false,
            version: None,
            message: "No Ruby manager found".to_string(),
        }
    }
}

pub fn get_status() -> DependenciesStatus {
    DependenciesStatus {
        homebrew: get_homebrew_status(),
        caddy: get_caddy_status(),
        mkcert: get_mkcert_status(),
        ruby: get_ruby_status(),
    }
}

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

pub fn install_caddy() -> Result<String> {
    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("brew install caddy")
        .output()?;

    if output.status.success() {
        Ok("Caddy installed successfully".to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Ok(format!("Failed to install Caddy: {}", stderr))
    }
}

pub fn install_mkcert() -> Result<String> {
    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("brew install mkcert")
        .output()?;

    if output.status.success() {
        Ok("mkcert installed successfully".to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Ok(format!("Failed to install mkcert: {}", stderr))
    }
}

pub fn run() -> Result<String> {
    let mut checks = Vec::new();
    let mut install_messages = Vec::new();

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
            "Not found - install from https://brew.sh".to_string()
        },
    });

    let caddy = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("which caddy")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    let caddy_check = if !caddy && homebrew {
        match install_caddy() {
            Ok(msg) => {
                install_messages.push(msg);
                true
            }
            Err(e) => false,
        }
    } else {
        caddy
    };

    checks.push(Check {
        name: "Caddy".to_string(),
        passed: caddy_check,
        message: if caddy_check {
            "Found".to_string()
        } else if !homebrew {
            "Not found (install Homebrew first)".to_string()
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

    let mkcert_check = if !mkcert && homebrew {
        match install_mkcert() {
            Ok(msg) => {
                install_messages.push(msg);
                true
            }
            Err(e) => false,
        }
    } else {
        mkcert
    };

    checks.push(Check {
        name: "mkcert".to_string(),
        passed: mkcert_check,
        message: if mkcert_check {
            "Found".to_string()
        } else if !homebrew {
            "Not found (install Homebrew first)".to_string()
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
            "Not found - install from https://rvm.io".to_string()
        },
    });

    let caddy_running = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg("pgrep -x caddy")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    let caddy_running_check = if !caddy_running && caddy {
        let plist_path = std::path::PathBuf::from("/Users/dannysimfukwe/Library/LaunchAgents/com.stable.caddy.plist");
        if !plist_path.exists() {
            let plist_content = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stable.caddy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/caddy</string>
        <string>run</string>
        <string>--adapter</string>
        <string>caddyfile</string>
        <string>--config</string>
        <string>/Users/dannysimfukwe/StableCaddy/projects/Caddyfile</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/caddy-stable.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/caddy-stable.err</string>
</dict>
</plist>
"#;
            let _ = std::fs::write(&plist_path, plist_content);
        }
        match std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg("launchctl load ~/Library/LaunchAgents/com.stable.caddy.plist")
            .output()
        {
            Ok(_) => {
                install_messages.push("Caddy started via LaunchAgent".to_string());
                true
            }
            Err(_) => false,
        }
    } else {
        caddy_running
    };
    checks.push(Check {
        name: "Caddy running".to_string(),
        passed: caddy_running_check,
        message: if caddy_running_check {
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

    if !install_messages.is_empty() {
        report.push_str("\n--- Auto-installed ---\n");
        for msg in &install_messages {
            report.push_str(&format!("  • {}\n", msg));
        }
    }

    let all_passed = checks.iter().all(|c| c.passed);
    report.push_str(if all_passed {
        "\nAll checks passed."
    } else {
        "\nSome checks failed."
    });

    Ok(report)
}
