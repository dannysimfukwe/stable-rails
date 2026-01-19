use crate::stable::config::{
    load_all_app_configs, load_app_config, save_app_config, update_caddyfile,
};
use crate::stable::ruby_manager::ensure_ruby_for_app;
use anyhow::Result;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

fn log(msg: &str) {
    println!("{}", msg);
    let log_path = PathBuf::from("/tmp/stable.log");
    let existing = fs::read_to_string(&log_path).unwrap_or_default();
    let _ = fs::write(&log_path, format!("{}{}\n", existing, msg));
}

fn find_pid_by_port(port: u16) -> Option<i32> {
    let output = Command::new("lsof")
        .arg("-i")
        .arg(format!(":{}", port))
        .output()
        .ok()?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if line.contains("LISTEN") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 1 {
                return parts[1].parse().ok();
            }
        }
    }
    None
}

pub fn run() -> Result<()> {
    let configs = load_all_app_configs()?;
    log(&format!("[start_all] Found {} apps", configs.len()));

    let mut started = Vec::new();
    for config in configs.iter() {
        let app_name = config.name.clone();
        let app_path = config.path.clone();
        let port = config.port;

        if !app_path.exists() {
            log(&format!(
                "[start_all] {} path does not exist, skipping",
                app_name
            ));
            continue;
        }

        let rails_bin = app_path.join("bin/rails");
        if !rails_bin.exists() {
            log(&format!(
                "[start_all] Missing bin/rails in {}",
                app_path.display()
            ));
            continue;
        }

        log(&format!(
            "[start_all] Starting {} on port {}...",
            app_name, port
        ));

        let (ruby_path, bundle_path) = match ensure_ruby_for_app(&app_path) {
            Ok(paths) => paths,
            Err(e) => {
                log(&format!(
                    "[start_all] Failed to get Ruby for {}: {}",
                    app_name, e
                ));
                continue;
            }
        };

        let status = Command::new("/bin/zsh")
            .arg("-lc")
            .arg(format!(
                "cd '{}' && nohup {} exec bin/rails server -p {} > /tmp/rails.log 2>&1 &",
                app_path.display(),
                bundle_path.display(),
                port
            ))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();

        match status {
            Ok(_) => {
                log(&format!("[start_all] Started {}", app_name));
                started.push((app_name, port));
            }
            Err(e) => {
                log(&format!("[start_all] Failed to start {}: {}", app_name, e));
            }
        }
    }

    if started.is_empty() {
        log("[start_all] No apps were started");
        anyhow::bail!("No apps were started");
    }

    log(&format!(
        "[start_all] Started {} apps, checking status...",
        started.len()
    ));

    std::thread::sleep(Duration::from_secs(3));

    let mut ready_count = 0;
    let mut checked_ports: Vec<u16> = Vec::new();

    for (app_name, port) in started.iter() {
        if let Some(pid) = find_pid_by_port(*port) {
            let mut config = load_app_config(app_name)?;
            config.pid = Some(pid);
            config.started_at = Some(chrono::Utc::now().timestamp());
            save_app_config(&config)?;
            log(&format!("[start_all] {} ready (PID: {})", app_name, pid));
            checked_ports.push(*port);
            ready_count += 1;
        }
    }

    log(&format!(
        "[start_all] {} of {} apps ready",
        ready_count,
        started.len()
    ));

    log("[start_all] Updating Caddyfile...");
    update_caddyfile()?;

    log("[start_all] Done");
    Ok(())
}
