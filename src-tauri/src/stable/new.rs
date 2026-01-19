use crate::stable::config::{AppConfig, next_available_port, save_app_config, update_caddyfile};
use crate::stable::utils::{
    apps_folder, ensure_hosts_entry, run_shell_output, shell_escape, slugify_name,
};
use anyhow::Result;
use std::fs;

pub fn run_with_progress<F, G>(app_name: &str, progress: F, log: G) -> Result<()>
where
    F: Fn(&str),
    G: Fn(&str),
{
    let apps_root = apps_folder();
    fs::create_dir_all(&apps_root)?;

    let slug_name = slugify_name(app_name);
    if slug_name != app_name {
        log(&format!(
            "Using '{}' as the app folder and domain.",
            slug_name
        ));
    }

    let app_path = apps_root.join(&slug_name);

    if app_path.exists() {
        anyhow::bail!("App '{}' already exists", slug_name);
    }

    let port = next_available_port();
    log(&format!("Assigning port {} to this app", port));

    let escaped_name = shell_escape(&slug_name);
    progress("Creating Rails app...");
    let rails_output = run_shell_output(
        &apps_root,
        &format!("rails new '{}' --skip-bundle", escaped_name),
    )?;
    log_output(&log, &rails_output);
    if !rails_output.status.success() {
        anyhow::bail!("rails new failed for '{}'", app_name);
    }

    let cert_path = app_path.join("cert.pem");
    let key_path = app_path.join("key.pem");

    let domain = format!("{}.test", slug_name);
    let _ = ensure_hosts_entry(&domain)?;

    if !cert_path.exists() || !key_path.exists() {
        progress("Generating TLS certificates...");
        let mkcert_output = run_shell_output(&app_path, &format!("mkcert '{}.test'", escaped_name));

        if let Ok(output) = mkcert_output {
            log_output(&log, &output);
            if output.status.success() {
                let generated_cert = app_path.join(format!("{}.test.pem", slug_name));
                let generated_key = app_path.join(format!("{}.test-key.pem", slug_name));
                if let Err(err) = fs::rename(generated_cert, &cert_path) {
                    log(&format!("Warning: could not move cert file: {}", err));
                }
                if let Err(err) = fs::rename(generated_key, &key_path) {
                    log(&format!("Warning: could not move key file: {}", err));
                }
            } else {
                log("mkcert failed; continuing without custom certs.");
            }
        }
    }

    let mut app_config = AppConfig::default();
    app_config.name = slug_name.clone();
    app_config.path = app_path.clone();
    app_config.port = port;
    app_config.domain = domain.clone();
    app_config.rails_env = "development".to_string();
    app_config.tls_enabled = true;
    app_config.caddy_enabled = true;
    save_app_config(&app_config)?;
    log(&format!("Saved config for {} on port {}", slug_name, port));

    progress("Updating Caddy configuration...");
    update_caddyfile()?;
    log("Caddy configuration updated.");

    progress("Stable app ready.");
    Ok(())
}

pub fn run(app_name: &str) -> Result<()> {
    run_with_progress(app_name, |_| {}, |_| {})
}

fn log_output<F>(log: &F, output: &std::process::Output)
where
    F: Fn(&str),
{
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if !line.trim().is_empty() {
            log(line);
        }
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    for line in stderr.lines() {
        if !line.trim().is_empty() {
            log(line);
        }
    }
}
