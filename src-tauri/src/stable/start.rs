use crate::stable::config::{
    apps_folder, find_pids_by_port, is_port_in_use, load_app_config, save_app_config,
    update_caddyfile,
};
use crate::stable::utils::ensure_hosts_entry;
use anyhow::Result;
use std::fs;
use std::process::Command;
use std::time::Duration;

pub fn run(app_name: &str) -> Result<()> {
    let config = load_app_config(app_name)?;
    let app_path = config.path.clone();

    if !app_path.exists() {
        anyhow::bail!("App folder '{}' does not exist", app_path.display());
    }

    let rails_bin = app_path.join("bin/rails");
    if !rails_bin.exists() {
        anyhow::bail!("Missing bin/rails in {}", app_path.display());
    }

    let port = config.port;

    let domain = format!("{}.test", app_name);
    let _ = ensure_hosts_entry(&domain);

    // Kill any existing process on this port
    let existing_pids = find_pids_by_port(port);
    if !existing_pids.is_empty() {
        for pid in existing_pids {
            let _ = Command::new("kill").arg("-9").arg(pid.to_string()).output();
        }
        std::thread::sleep(Duration::from_millis(200));
    }

    let spawn_result = Command::new("bash")
        .arg("-c")
        .arg(format!(
            "source ~/.rvm/scripts/rvm && export GEM_HOME=$(~/.rvm/gems/ruby-3.4.7@gemsets global gem env GEM_HOME 2>/dev/null || echo ~/.rvm/gems/ruby-3.4.7) && export PATH=\"$GEM_HOME/bin:$PATH\" && cd '{}' && nohup ~/.rvm/rubies/ruby-3.4.7/bin/ruby ~/.rvm/gems/ruby-3.4.7/bin/bundle exec bin/rails server -p {} > /dev/null 2>&1 &",
            app_path.display(),
            port
        ))
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();

    if let Err(e) = spawn_result {
        anyhow::bail!("Failed to spawn Rails server: {}", e);
    }

    Ok(())
}
