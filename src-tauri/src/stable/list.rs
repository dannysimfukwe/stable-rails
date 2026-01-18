use crate::stable::config::load_app_config;
use crate::stable::utils::load_apps;
use anyhow::Result;

#[derive(Debug, Clone, serde::Serialize)]
pub struct AppInfo {
    pub name: String,
    pub url: String,
    pub port: u16,
    pub status: String,
}

pub fn run() -> Result<Vec<AppInfo>> {
    let apps = load_apps()?;
    let mut app_infos = Vec::new();

    for name in apps {
        let config = load_app_config(&name).unwrap_or_default();
        let url = format!("https://{}.test", name);
        app_infos.push(AppInfo {
            name,
            url,
            port: config.port,
            status: "stopped".to_string(),
        });
    }

    Ok(app_infos)
}
