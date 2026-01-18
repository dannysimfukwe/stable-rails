use anyhow::Result;
use std::ffi::OsStr;
use std::path::Path;
use sysinfo::{ProcessesToUpdate, System};

pub fn run(app_name: &str) -> Result<()> {
    let app_path = dirs::home_dir()
        .expect("Cannot find home directory")
        .join(".stable_apps")
        .join(app_name);

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_name);
    }

    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);

    let app_osstr = OsStr::new(app_name);

    for process in sys.processes_by_name(app_osstr) {
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

    Ok(())
}
