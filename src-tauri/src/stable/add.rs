use crate::stable::config::{
    AppConfig, apps_folder, find_available_port_for_app, save_app_config, update_global_caddyfile,
};
use crate::stable::utils::{ensure_hosts_entry, run_shell_output, shell_escape};
use anyhow::Result;
use std::path::Path;

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
        anyhow::bail!("App '{}' already exists in ~/.stable_apps", app_name);
    }

    std::fs::rename(folder_path, &target)?;

    let port = find_available_port_for_app(&app_name)?;
    let domain = format!("{}.test", app_name);

    let hosts_added = ensure_hosts_entry(&domain)?;
    if hosts_added {
        println!("Added hosts entry for {}", domain);
    }

    let cert_path = target.join("cert.pem");
    let key_path = target.join("key.pem");

    if !cert_path.exists() || !key_path.exists() {
        let escaped_name = shell_escape(&app_name);
        let _ = run_shell_output(&target, &format!("mkcert '{}.test'", escaped_name));
        if target.join(format!("{}.test.pem", app_name)).exists() {
            let _ = std::fs::rename(target.join(format!("{}.test.pem", app_name)), &cert_path);
        }
        if target.join(format!("{}-key.pem", app_name)).exists() {
            let _ = std::fs::rename(target.join(format!("{}-key.pem", app_name)), &key_path);
        }
    }

    let mut app_config = AppConfig::default();
    app_config.name = app_name.clone();
    app_config.port = port;
    app_config.domain = domain;
    app_config.rails_env = "development".to_string();
    app_config.tls_enabled = true;
    app_config.caddy_enabled = true;
    save_app_config(&app_name, &app_config)?;

    update_global_caddyfile()?;

    Ok(())
}
