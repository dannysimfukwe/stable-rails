use crate::stable::config::{
    apps_folder, find_pids_by_port, load_app_config, save_app_config, update_caddyfile,
};
use anyhow::Result;
use std::process::Command;
use std::time::Duration;

pub fn run(app_name: &str) -> Result<()> {
    let config = load_app_config(app_name)?;
    let port = config.port;

    println!("Stopping app '{}' on port {}", app_name, port);

    // Find and kill processes on this port
    let pids = find_pids_by_port(port);

    if pids.is_empty() {
        println!("No process on port {}", port);
    } else {
        for pid in &pids {
            println!("Killing PID {}", pid);
            let _ = Command::new("kill").arg("-9").arg(pid.to_string()).output();
        }
        std::thread::sleep(Duration::from_millis(300));
    }

    // Clear config
    let mut config = load_app_config(app_name)?;
    config.pid = None;
    config.started_at = None;
    save_app_config(&config)?;

    update_caddyfile()?;

    println!("Stop complete for {}", app_name);
    Ok(())
}
