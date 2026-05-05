use crate::stable::config::{
    AppConfig, apps_folder, next_available_port, save_app_config, update_caddyfile,
};
use crate::stable::utils::{ensure_hosts_entry, run_shell_output, shell_escape};
use anyhow::Result;
use std::fs;
use std::path::Path;
use std::path::PathBuf;

pub fn run(folder: &str) -> Result<()> {
    let folder_path = Path::new(folder);
    if !folder_path.exists() {
        anyhow::bail!("Folder '{}' does not exist", folder);
    }

    let app_name = folder_path
        .file_name()
        .unwrap()
        .to_string_lossy()
        .to_string();
    let target = apps_folder().join(&app_name);

    if target.exists() {
        anyhow::bail!(
            "App '{}' already exists in ~/StableCaddy/projects",
            app_name
        );
    }

    std::fs::rename(folder_path, &target)?;

    let port = next_available_port();
    let domain = format!("{}.test", app_name);

    let _ = ensure_hosts_entry(&domain)?;

    let cert_path = target.join("cert.pem");
    let key_path = target.join("key.pem");

    if !cert_path.exists() || !key_path.exists() {
        let escaped_name = shell_escape(&app_name);
        let _ = run_shell_output(&target, &format!("mkcert '{}.test'", escaped_name));
        // Move generated certs to expected locations
        let generated_cert = target.join(format!("{}.test.pem", app_name));
        let generated_key = target.join(format!("{}.test-key.pem", app_name));
        if generated_cert.exists() {
            let _ = fs::rename(&generated_cert, &cert_path);
        }
        if generated_key.exists() {
            let _ = fs::rename(&generated_key, &key_path);
        }
    }

    let mut app_config = AppConfig::default();
    app_config.name = app_name.clone();
    app_config.path = target.clone();
    app_config.port = port;
    app_config.domain = domain;
    app_config.rails_env = "development".to_string();
    app_config.tls_enabled = true;
    app_config.caddy_enabled = true;
    save_app_config(&app_config)?;

    update_caddyfile()?;

    Ok(())
}
