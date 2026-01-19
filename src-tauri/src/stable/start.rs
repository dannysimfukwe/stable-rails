use crate::stable::config::{apps_folder, load_all_app_configs, load_app_config, save_app_config};
use crate::stable::utils::{ensure_hosts_entry, run_shell};
use anyhow::Result;
use std::fs;
use std::process::Command;
use std::time::Duration;

pub fn run(app_name: &str) -> Result<()> {
    let app_path = apps_folder().join(app_name);

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_path.display());
    }

    let rails_bin = app_path.join("bin/rails");
    if !rails_bin.exists() {
        anyhow::bail!("Missing bin/rails in {}", app_path.display());
    }

    let mut config = load_app_config(app_name)?;
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

    let spawn_result = Command::new("nohup")
        .arg(&rails_bin)
        .arg("server")
        .arg("-p")
        .arg(port.to_string())
        .current_dir(&app_path)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();

    if let Err(e) = spawn_result {
        anyhow::bail!("Failed to spawn Rails server: {}", e);
    }

    std::thread::sleep(Duration::from_millis(1500));

    let port_str = port.to_string();
    let mut found_pid: Option<i32> = None;

    let pgrep_output = Command::new("pgrep")
        .arg("-f")
        .arg(format!("rails server.*{}", port_str))
        .output();

    match pgrep_output {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !stdout.is_empty() {
                if let Ok(pid) = stdout.parse() {
                    found_pid = Some(pid);
                }
            }
        }
        Err(e) => {
            println!("pgrep failed: {}", e);
        }
    }

    if found_pid.is_none() {
        let lsof_output = Command::new("lsof")
            .arg("-ti")
            .arg(format!(":{}", port_str))
            .output();

        if let Ok(output) = lsof_output {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !stdout.is_empty() {
                if let Ok(pid) = stdout.parse() {
                    found_pid = Some(pid);
                }
            }
        }
    }

    if let Some(pid) = found_pid {
        config.pid = Some(pid);
        config.time_started = Some(chrono::Utc::now().timestamp());
        println!("Started app '{}' with PID {}", app_name, pid);
    } else {
        println!(
            "Warning: Could not find PID for app '{}' on port {}",
            app_name, port_str
        );
    }

    save_app_config(app_name, &config)?;

    update_global_caddyfile()?;

    Ok(())
}

fn update_global_caddyfile() -> Result<()> {
    let global_caddyfile = apps_folder().join("Caddyfile");
    let mut content = String::new();

    let all_configs = load_all_app_configs()?;

    for config in all_configs {
        if !config.caddy_enabled {
            continue;
        }

        let domain = format!("{}.test", config.name);
        let cert_path = apps_folder().join(&config.name).join("cert.pem");
        let key_path = apps_folder().join(&config.name).join("key.pem");

        content.push_str(&format!("{} {{\n", domain));

        if config.tls_enabled {
            if cert_path.exists() && key_path.exists() {
                content.push_str(&format!(
                    "    tls {} {}\n",
                    cert_path.display(),
                    key_path.display()
                ));
            } else {
                content.push_str("    tls internal\n");
            }
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

    if let Err(_) = status {
        let _ = run_shell(
            &apps_folder(),
            &format!("caddy start --config '{}'", global_caddyfile.display()),
        )
        .map_err(|e| println!("Caddy start warning: {}", e));
    }

    Ok(())
}
