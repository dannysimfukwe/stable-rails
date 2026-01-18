use crate::stable::utils::apps_folder;
use anyhow::Result;
use std::path::Path;

pub fn run(folder: &str) -> Result<()> {
    let folder_path = Path::new(folder);
    if !folder_path.exists() {
        anyhow::bail!("Folder '{}' does not exist", folder);
    }

    let target = apps_folder().join(folder_path.file_name().unwrap());
    std::fs::rename(folder_path, target)?;
    Ok(())
}
