use crate::stable::utils::apps_folder;
use anyhow::Result;
use std::fs;

pub fn run(name: &str) -> Result<()> {
    let app_path = apps_folder().join(name);
    if app_path.exists() {
        fs::remove_dir_all(&app_path)?;
    }
    Ok(())
}
