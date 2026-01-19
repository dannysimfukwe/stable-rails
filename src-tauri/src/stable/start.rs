use crate::stable::config::{find_pids_by_port, load_app_config, save_app_config};
use crate::stable::ruby_manager::ensure_ruby_for_app;
use crate::stable::utils::ensure_hosts_entry;
use anyhow::Result;
use std::process::Command;
use std::time::Duration;

pub fn run(app_name: &str) -> Result<()> {
    let config = load_app_config(app_name)?;
    let app_path = config.path.clone();

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_path.display());
    }

    let rails_bin = app_path.join("bin/rails");
    if !rails_bin.exists() {
        anyhow::bail!("Missing bin/rails in {}", app_path.display());
    }

    let port = config.port;

    let domain = format!("{}.test", app_name);
    let _ = ensure_hosts_entry(&domain);

    let existing_pids = find_pids_by_port(port);
    if !existing_pids.is_empty() {
        for pid in existing_pids {
            let _ = Command::new("kill").arg("-9").arg(pid.to_string()).output();
        }
        std::thread::sleep(Duration::from_millis(200));
    }

    let (ruby_path, bundle_path) = ensure_ruby_for_app(&app_path)?;

    let spawn_result = Command::new("/bin/zsh")
        .arg("-lc")
        .arg(format!(
            "cd '{}' && nohup {} exec bin/rails server -p {} > /tmp/rails.log 2>&1 &",
            app_path.display(),
            bundle_path.display(),
            port
        ))
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();

    if let Err(e) = spawn_result {
        anyhow::bail!("Failed to spawn Rails server: {}", e);
    }

    // Wait for the server to start and bind to the port
    std::thread::sleep(Duration::from_secs(3));

    // Check if the app is running and save config
    let pids = find_pids_by_port(port);
    if let Some(first_pid) = pids.first() {
        let mut config = load_app_config(app_name)?;
        config.pid = Some(*first_pid);
        config.started_at = Some(chrono::Utc::now().timestamp());
        save_app_config(&config)?;
    }

    Ok(())
}
