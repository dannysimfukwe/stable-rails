use crate::stable::utils::{
    apps_folder, ensure_hosts_entry, run_shell, run_shell_spawn, shell_escape,
};
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

    run_shell_spawn(&app_path, "./bin/rails server")?;

    let caddyfile_path = app_path.join("Caddyfile");
    if !caddyfile_path.exists() {
        let cert_path = app_path.join("cert.pem");
        let key_path = app_path.join("key.pem");
        let mut content = format!("{}.test {{\n", app_name);
        if cert_path.exists() && key_path.exists() {
            content.push_str(&format!(
                "    tls {} {}\n",
                cert_path.display(),
                key_path.display()
            ));
        } else {
            content.push_str("    tls internal\n");
        }
        content.push_str("    reverse_proxy 127.0.0.1:3000\n}\n");
        fs::write(&caddyfile_path, content)?;
    }

    let caddy_path = shell_escape(&caddyfile_path.to_string_lossy());
    let status = run_shell(
        &app_path,
        &format!("caddy reload --config '{}'", caddy_path),
    )
    .map_err(|err| anyhow::anyhow!("Failed to run caddy: {}", err))?;

    if !status.success() {
        let caddy_start = run_shell(&app_path, &format!("caddy start --config '{}'", caddy_path));
        if let Ok(start_status) = caddy_start {
            if !start_status.success() {
                println!("Warning: Caddy reload/start failed, check Caddy logs");
            }
        } else {
            println!("Warning: Caddy reload/start failed, check Caddy logs");
        }
    }

    Ok(())
}
