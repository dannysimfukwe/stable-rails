use crate::stable::config::{
    apps_folder, load_app_config, save_app_config, update_global_caddyfile,
};
use anyhow::Result;
use std::ffi::{OsStr, OsString};
use sysinfo::{Pid, ProcessesToUpdate, System};

fn cmdline_to_string(cmd: &[OsString]) -> String {
    cmd.iter()
        .map(|arg| arg.to_string_lossy().to_string())
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn run(app_name: &str) -> Result<()> {
    let app_path = apps_folder().join(app_name);

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_name);
    }

    let mut config = load_app_config(app_name).ok().unwrap_or_default();
    let port = config.port;
    let port_str = port.to_string();

    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);

    println!("Stopping app '{}' on port {}", app_name, port_str);

    if let Some(pid) = config.pid {
        println!("Killing stored PID: {}", pid);
        if let Some(process) = sys.process(Pid::from_u32(pid as u32)) {
            println!(
                "Found process, killing: {}",
                cmdline_to_string(process.cmd())
            );
            let _ = process.kill();
        }
        let _ = std::process::Command::new("kill")
            .arg("-9")
            .arg(pid.to_string())
            .output();
    }

    let _ = std::process::Command::new("pkill")
        .arg("-9")
        .arg("-f")
        .arg(&format!("rails server.*{}", port_str))
        .output();

    let _ = std::process::Command::new("pkill")
        .arg("-9")
        .arg("-f")
        .arg(&format!("ruby.*-p {}", port_str))
        .output();

    let _ = std::process::Command::new("pkill")
        .arg("-9")
        .arg("-f")
        .arg(&format!("rackup.*-p {}", port_str))
        .output();

    let lsof_output = std::process::Command::new("lsof")
        .arg("-ti")
        .arg(&format!(":{}", port_str))
        .output();

    if let Ok(output) = lsof_output {
        let pids = String::from_utf8_lossy(&output.stdout);
        for pid in pids.split_whitespace() {
            println!("lsof found PID: {}, killing", pid);
            let _ = std::process::Command::new("kill")
                .arg("-9")
                .arg(pid)
                .output();
        }
    }

    sys.refresh_processes(ProcessesToUpdate::All, true);

    println!(
        "Looking for any Ruby/Rails processes on port {}...",
        port_str
    );
    for process in sys.processes_by_name(OsStr::new("ruby")) {
        let cmdline = cmdline_to_string(process.cmd());
        let has_port = cmdline.contains(&format!("-p {}", port_str))
            || cmdline.contains(&format!("--port {}", port_str))
            || cmdline.contains("rails server")
            || cmdline.contains("bin/rails server")
            || cmdline.contains("PASSENGER_APP_ROOT")
            || cmdline.contains(&app_name);

        if has_port {
            println!("Found ruby process to kill: {}", cmdline);
            let _ = process.kill();
        }
    }

    println!("Also checking ALL ruby processes for safety...");
    for process in sys.processes_by_name(OsStr::new("ruby")) {
        let cmdline = cmdline_to_string(process.cmd());
        if cmdline.contains("rails server") || cmdline.contains("bin/rails") {
            println!("Killing Rails process: {}", cmdline);
            let _ = process.kill();
        }
    }

    let _ = std::process::Command::new("pkill")
        .arg("-9")
        .arg("-f")
        .arg(&format!("rails server"))
        .output();

    let _ = std::process::Command::new("pkill")
        .arg("-9")
        .arg("-f")
        .arg(&format!("caddy.*{}", port_str))
        .output();

    std::thread::sleep(std::time::Duration::from_millis(500));

    sys.refresh_processes(ProcessesToUpdate::All, true);

    let mut still_running = false;
    for process in sys.processes_by_name(OsStr::new("ruby")) {
        let cmdline = cmdline_to_string(process.cmd());
        let has_port = cmdline.contains(&format!("-p {}", port_str))
            || cmdline.contains("rails server")
            || cmdline.contains(&app_name);

        if has_port {
            println!("WARNING: Process still running: {}", cmdline);
            still_running = true;
            let _ = process.kill();
        }
    }

    if still_running {
        println!("Force killing all rails server processes...");
        let _ = std::process::Command::new("pkill")
            .arg("-9")
            .arg("-f")
            .arg("rails server")
            .output();
    }

    config.pid = None;
    config.time_started = None;
    let _ = save_app_config(app_name, &config);

    let _ = update_global_caddyfile();

    println!("Stop complete for {}", app_name);
    Ok(())
}
