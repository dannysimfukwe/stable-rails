use crate::stable::config::{load_app_config, update_global_caddyfile};
use anyhow::Result;
use std::ffi::{OsStr, OsString};
use std::path::Path;
use sysinfo::{ProcessesToUpdate, System};

fn cmdline_to_string(cmd: &[OsString]) -> String {
    cmd.iter()
        .map(|arg| arg.to_string_lossy().to_string())
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn run(app_name: &str) -> Result<()> {
    let app_path = dirs::home_dir()
        .expect("Cannot find home directory")
        .join(".stable_apps")
        .join(app_name);

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_name);
    }

    let config = load_app_config(app_name).ok();
    let port = config.as_ref().map(|c| c.port).unwrap_or(3000);

    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);

    for process in sys.processes_by_name(OsStr::new("ruby")) {
        let cmdline = cmdline_to_string(process.cmd());
        let has_app_name = cmdline.contains(app_name);
        let has_port = cmdline.contains(&format!("-p {}", port))
            || cmdline.contains(&format!("--port {}", port));

        if has_app_name && (has_port || cmdline.contains("rails server")) {
            process.kill();
        }
    }

    for process in sys.processes_by_name(OsStr::new("caddy")) {
        let cmdline = cmdline_to_string(process.cmd());
        if cmdline.contains(app_name) || cmdline.contains(&format!(":{}", port)) {
            process.kill();
        }
    }

    for process in sys.processes_by_name(OsStr::new(app_name)) {
        if let Some(cwd) = process.cwd() {
            if cwd == Path::new(&app_path) {
                process.kill();
            }
        }
    }

    for process in sys.processes_by_name(OsStr::new("caddy")) {
        if let Some(cwd) = process.cwd() {
            if cwd == Path::new(&app_path) {
                process.kill();
            }
        }
    }

    update_global_caddyfile()?;

    Ok(())
}
