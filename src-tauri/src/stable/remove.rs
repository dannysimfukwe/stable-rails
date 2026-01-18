use crate::stable::config::{delete_app_config, update_global_caddyfile};
use crate::stable::utils::{apps_folder, run_shell, run_shell_output};
use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

pub fn run(name: &str) -> Result<()> {
    let app_path = apps_folder().join(name);
    if !app_path.exists() {
        return Ok(());
    }

    let domain = format!("{}.test", name);

    let _ = run_shell(&app_path, &format!("pkill -f 'rails server' 2>/dev/null"));
    let _ = run_shell(&app_path, "pkill -f caddy 2>/dev/null");

    let cert_path = app_path.join("cert.pem");
    let key_path = app_path.join("key.pem");
    let _ = fs::remove_file(&cert_path);
    let _ = fs::remove_file(&key_path);

    let hosts_contents = fs::read_to_string("/etc/hosts").unwrap_or_default();
    if hosts_contents.contains(&domain) {
        let script = format!(
            "sed -i '' '/127.0.0.1\\t{}/d' /etc/hosts",
            domain.replace('"', "\\\"")
        );
        let _ = run_shell_output(Path::new("/"), &script);
    }

    let _ = delete_app_config(name)?;

    fs::remove_dir_all(&app_path)
        .with_context(|| format!("Failed to remove {}", app_path.display()))?;

    update_global_caddyfile()?;

    Ok(())
}
