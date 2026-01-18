use crate::stable::utils::load_apps;
use anyhow::Result;

pub fn run() -> Result<Vec<String>> {
    let apps = load_apps()?;
    Ok(apps)
}
