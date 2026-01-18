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

    let escaped_name = shell_escape(&slug_name);
    progress("Creating Rails app...");
    let rails_output = run_shell_output(&apps_root, &format!("rails new '{}'", escaped_name))?;
    log_output(&log, &rails_output);
    if !rails_output.status.success() {
        anyhow::bail!("rails new failed for '{}'", app_name);
    }

    let cert_path = app_path.join("cert.pem");
    let key_path = app_path.join("key.pem");

    let domain = format!("{}.test", slug_name);
    let hosts_added = ensure_hosts_entry(&domain)?;
    if hosts_added {
        log(&format!("Added hosts entry for {}", domain));
    }

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

    let caddyfile_path = app_path.join("Caddyfile");
    let mut caddyfile_content = format!("{}.test {{\n", slug_name);

    if cert_path.exists() && key_path.exists() {
        caddyfile_content.push_str(&format!(
            "    tls {} {}\n",
            cert_path.display(),
            key_path.display()
        ));
    } else {
        caddyfile_content.push_str("    tls internal\n");
    }

    caddyfile_content.push_str("    reverse_proxy 127.0.0.1:3000\n}\n");

    log(&format!("App domain: https://{}", domain));
    if let Err(err) = fs::write(&caddyfile_path, caddyfile_content) {
        log(&format!("Failed to write Caddyfile: {}", err));
        return Err(err.into());
    }

    progress("Reloading Caddy...");
    let caddy_path = shell_escape(&caddyfile_path.to_string_lossy());
    let reload_status = run_shell_output(
        &app_path,
        &format!("caddy reload --config '{}'", caddy_path),
    );
    if let Ok(output) = reload_status {
        log_output(&log, &output);
        if !output.status.success() {
            let start_output =
                run_shell_output(&app_path, &format!("caddy start --config '{}'", caddy_path));
            if let Ok(started) = start_output {
                log_output(&log, &started);
            }
        }
    }

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
