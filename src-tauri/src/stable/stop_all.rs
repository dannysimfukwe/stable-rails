use crate::stable::config::{
    load_all_app_configs, load_app_config, save_app_config, update_caddyfile,
};
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

pub fn run() -> Result<()> {
    let configs = load_all_app_configs()?;
    log(&format!("[stop_all] Found {} apps", configs.len()));

    // Kill all processes by port using lsof
    log("[stop_all] Killing processes...");
    for config in configs.iter() {
        let port = config.port;

        // Use lsof to find PIDs by port
        let output = Command::new("lsof")
            .arg("-i")
            .arg(format!(":{}", port))
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if line.contains("LISTEN") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() > 1 {
                    if let Ok(pid) = parts[1].parse::<i32>() {
                        log(&format!(
                            "[stop_all] Killing {} (PID: {})",
                            config.name, pid
                        ));
                        let _ = Command::new("kill").arg("-9").arg(pid.to_string()).output();
                    }
                }
            }
        }
    }

    // Wait for processes to die
    std::thread::sleep(Duration::from_millis(500));

    // Clear configs
    for config in configs {
        let mut config = load_app_config(&config.name)?;
        config.pid = None;
        config.started_at = None;
        save_app_config(&config)?;
        log(&format!("[stop_all] {} stopped", config.name));
    }

    log("[stop_all] Updating Caddyfile...");
    update_caddyfile()?;

    log("[stop_all] Done");
    Ok(())
}
