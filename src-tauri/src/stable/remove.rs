use crate::stable::utils::apps_folder;
use anyhow::{Context, Result};
use std::fs;

pub fn run(name: &str) -> Result<()> {
    let app_path = apps_folder().join(name);
    if !app_path.exists() {
        return Ok(());
    }
    fs::remove_dir_all(&app_path)
        .with_context(|| format!("Failed to remove {}", app_path.display()))?;
    Ok(())
}
