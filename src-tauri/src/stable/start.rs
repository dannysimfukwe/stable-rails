use crate::stable::config::{apps_folder, load_all_app_configs, load_app_config};
use crate::stable::utils::{ensure_hosts_entry, run_shell, run_shell_spawn};
use anyhow::Result;
use std::fs;

pub fn run(app_name: &str) -> Result<()> {
    let app_path = apps_folder().join(app_name);

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_path.display());
    }

    let rails_bin = app_path.join("bin/rails");
    if !rails_bin.exists() {
        anyhow::bail!("Missing bin/rails in {}", app_path.display());
    }

    let config = load_app_config(app_name)?;
    let port = config.port;

    let domain = format!("{}.test", app_name);
    let hosts_added = ensure_hosts_entry(&domain)?;
    if !hosts_added {
        let hosts_contents = fs::read_to_string("/etc/hosts").unwrap_or_default();
        if !hosts_contents.contains(&domain) {
            anyhow::bail!(
                "Missing hosts entry for {}. Add `127.0.0.1 {}` to /etc/hosts.",
                domain,
                domain
            );
        }
    }

    run_shell_spawn(&app_path, &format!("./bin/rails server -p {}", port))?;

    update_global_caddyfile()?;

    Ok(())
}

fn update_global_caddyfile() -> Result<()> {
    let global_caddyfile = apps_folder().join("Caddyfile");
    let mut content = String::new();

    let all_configs = load_all_app_configs()?;

    for config in all_configs {
        let domain = format!("{}.test", config.name);
        let cert_path = apps_folder().join(&config.name).join("cert.pem");
        let key_path = apps_folder().join(&config.name).join("key.pem");

        content.push_str(&format!("{} {{\n", domain));

        if cert_path.exists() && key_path.exists() {
            content.push_str(&format!(
                "    tls {} {}\n",
                cert_path.display(),
                key_path.display()
            ));
        } else {
            content.push_str("    tls internal\n");
        }
        content.push_str(&format!(
            "    reverse_proxy 127.0.0.1:{}\n}}\n",
            config.port
        ));
    }

    fs::write(&global_caddyfile, content)?;

    let status = run_shell(
        &apps_folder(),
        &format!("caddy reload --config '{}'", global_caddyfile.display()),
    );

    if let Err(err) = status {
        let _ = run_shell(
            &apps_folder(),
            &format!("caddy start --config '{}'", global_caddyfile.display()),
        )
        .map_err(|e| println!("Caddy start warning: {}", e));
    }

    Ok(())
}
