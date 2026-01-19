use crate::stable::config::{apps_folder, is_port_in_use, load_all_app_configs};
use anyhow::Result;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

#[derive(Debug, Clone, serde::Serialize)]
pub struct AppInfo {
    pub name: String,
    pub url: String,
    pub port: u16,
    pub status: String,
}

lazy_static::lazy_static! {
    static ref LOG_FILE: Mutex<PathBuf> = Mutex::new(PathBuf::from("/tmp/stable.log"));
}

fn log(msg: &str) {
    let log_path = LOG_FILE.lock().unwrap().clone();
    let existing = fs::read_to_string(&log_path).unwrap_or_default();
    let _ = fs::write(&log_path, format!("{}{}\n", existing, msg));
}

pub fn run() -> Result<Vec<AppInfo>> {
    let apps = load_all_app_configs()?;

    log(&format!("[list_apps] Found {} apps", apps.len()));

    let mut app_infos = Vec::new();

    for config in apps {
        let url = format!("https://{}", config.domain);
        let port = config.port;

        // Check if port is in use - simple and reliable
        let running = is_port_in_use(port);
        let status = if running { "running" } else { "stopped" };

        log(&format!(
            "[list_apps] {}: port={}, status={}",
            config.name, port, status
        ));

        app_infos.push(AppInfo {
            name: config.name,
            url,
            port,
            status: status.to_string(),
        });
    }

    Ok(app_infos)
}
