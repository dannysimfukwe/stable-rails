use crate::stable::utils::load_apps;
use anyhow::Result;

pub fn run() -> Result<String> {
    let apps = load_apps()?;
    let mut report = String::from("Stable Doctor Report:\n");
    report.push_str(&format!("Detected apps: {}\n", apps.len()));
    for app in apps {
        report.push_str(&format!(" - {}\n", app));
    }
    Ok(report)
}
