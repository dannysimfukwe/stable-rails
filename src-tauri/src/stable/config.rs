use anyhow::Result;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use yaml_rust::{Yaml, YamlLoader};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppConfig {
    pub name: String,
    pub path: PathBuf,
    pub port: u16,
    pub ruby: Option<String>,
    pub rails_env: String,
    pub tls_enabled: bool,
    pub caddy_enabled: bool,
    pub domain: String,
    pub pid: Option<i32>,
    pub started_at: Option<i64>,
}

impl Default for AppConfig {
    fn default() -> Self {
        AppConfig {
            name: String::new(),
            path: PathBuf::new(),
            port: 3000,
            ruby: None,
            rails_env: "development".to_string(),
            tls_enabled: true,
            caddy_enabled: true,
            domain: String::new(),
            pid: None,
            started_at: None,
        }
    }
}

pub fn apps_folder() -> PathBuf {
    Path::new("~/StableCaddy/projects").expand_home()
}

fn load_yaml(path: &Path) -> Option<Yaml> {
    if !path.exists() {
        return None;
    }
    match fs::read_to_string(path) {
        Ok(content) => {
            let cleaned: String = content
                .lines()
                .map(|line| {
                    let trimmed = line.trim_start();
                    if trimmed.starts_with(":") {
                        let rest = &trimmed[1..];
                        if let Some(pos) = rest.find(": ") {
                            let key = &rest[..pos];
                            let val = &rest[pos + 1..];
                            format!("{}:{}", key, val)
                        } else {
                            line.to_string()
                        }
                    } else {
                        line.to_string()
                    }
                })
                .collect::<Vec<_>>()
                .join("\n");
            let docs = YamlLoader::load_from_str(&cleaned).ok()?;
            for doc in &docs {
                if let Some(n) = doc["name"].as_str() {
                    return Some(doc.clone());
                }
                if let Some(_n) = doc[":name"].as_str() {
                    return Some(doc.clone());
                }
            }
            docs.first().cloned()
        }
        Err(_) => None,
    }
}

pub fn load_app_config(app_name: &str) -> Result<AppConfig> {
    let app_folder = apps_folder().join(app_name);

    let config_path = app_folder.join(format!("{}.yml", app_name));
    let stable_config_path = app_folder.join(".stable.yml");

    let config_path = if config_path.exists() {
        config_path
    } else if stable_config_path.exists() {
        stable_config_path
    } else {
        anyhow::bail!(
            "No config file found for '{}' (tried {}.yml and .stable.yml)",
            app_name,
            app_folder.display()
        );
    };

    let mut config = AppConfig::default();
    config.name = app_name.to_string();
    config.domain = format!("{}.test", app_name);

    if let Some(yaml) = load_yaml(&config_path) {
        if let Some(port) = yaml["port"].as_i64().or(yaml[":port"].as_i64()) {
            config.port = port as u16;
        }
        if let Some(path) = yaml["path"].as_str().or(yaml[":path"].as_str()) {
            if !path.is_empty() {
                config.path = PathBuf::from(path);
            }
        }
        if config.path.as_os_str().is_empty() {
            config.path = app_folder.clone();
        }
        if let Some(ruby) = yaml["ruby"].as_str().or(yaml[":ruby"].as_str()) {
            config.ruby = Some(ruby.to_string());
        }
        if let Some(env) = yaml["rails_env"].as_str().or(yaml[":rails_env"].as_str()) {
            config.rails_env = env.to_string();
        }
        if let Some(tls) = yaml["tls_enabled"]
            .as_bool()
            .or(yaml[":tls_enabled"].as_bool())
        {
            config.tls_enabled = tls;
        }
        if let Some(caddy) = yaml["caddy_enabled"]
            .as_bool()
            .or(yaml[":caddy_enabled"].as_bool())
        {
            config.caddy_enabled = caddy;
        }
        if let Some(domain) = yaml["domain"].as_str().or(yaml[":domain"].as_str()) {
            config.domain = domain.to_string();
        }
        if let Some(pid) = yaml["pid"].as_i64().or(yaml[":pid"].as_i64()) {
            config.pid = Some(pid as i32);
        }
        if let Some(ts) = yaml["started_at"].as_i64().or(yaml[":started_at"].as_i64()) {
            config.started_at = Some(ts);
        }
    } else {
        config.path = app_folder.clone();
    }

    Ok(config)
}

pub fn save_app_config(app: &AppConfig) -> Result<()> {
    let app_folder = apps_folder().join(&app.name);
    fs::create_dir_all(&app_folder)?;

    let config_path = app_folder.join(format!("{}.yml", app.name));
    let mut content = String::new();

    content.push_str(&format!(":name: {}\n", app.name));
    content.push_str(&format!(":path: {}\n", app.path.display()));
    content.push_str(&format!(":port: {}\n", app.port));
    if let Some(ruby) = &app.ruby {
        content.push_str(&format!(":ruby: {}\n", ruby));
    }
    content.push_str(&format!(":rails_env: {}\n", app.rails_env));
    content.push_str(&format!(":tls_enabled: {}\n", app.tls_enabled));
    content.push_str(&format!(":caddy_enabled: {}\n", app.caddy_enabled));
    content.push_str(&format!(":domain: {}\n", app.domain));
    if let Some(pid) = app.pid {
        content.push_str(&format!(":pid: {}\n", pid));
    }
    if let Some(ts) = app.started_at {
        content.push_str(&format!(":started_at: {}\n", ts));
    }

    fs::write(&config_path, content)?;
    Ok(())
}

pub fn load_all_app_configs() -> Result<Vec<AppConfig>> {
    let root = apps_folder();
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut configs = Vec::new();
    for entry in fs::read_dir(&root)? {
        let entry = entry?;
        if entry.path().is_dir() {
            let name = entry.file_name().to_string_lossy().to_string();
            if let Ok(config) = load_app_config(&name) {
                configs.push(config);
            }
        }
    }
    Ok(configs)
}

pub fn delete_app_config(app_name: &str) -> Result<()> {
    let config_path = apps_folder()
        .join(app_name)
        .join(format!("{}.yml", app_name));
    if config_path.exists() {
        fs::remove_file(&config_path)?;
    }
    Ok(())
}

pub fn is_port_in_use(port: u16) -> bool {
    std::net::TcpListener::bind(("127.0.0.1", port)).is_err()
}

pub fn find_pids_by_port(port: u16) -> Vec<i32> {
    let output = std::process::Command::new("lsof")
        .args(&["-i", &format!(":{}", port), "-t"])
        .output();

    match output {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            stdout
                .split_whitespace()
                .filter_map(|pid| pid.parse().ok())
                .collect()
        }
        Err(_) => Vec::new(),
    }
}

pub fn port_available(port: u16) -> bool {
    !is_port_in_use(port)
}

pub fn next_available_port() -> u16 {
    let mut port = 3000;
    while !port_available(port) {
        port += 1;
    }
    port
}

pub fn update_caddyfile() -> Result<()> {
    use crate::stable::utils::run_shell;

    let caddyfile = apps_folder().join("Caddyfile");
    let certs_folder = PathBuf::from("/Users/dannysimfukwe/StableCaddy/certs");
    let mut content = String::new();

    for config in load_all_app_configs()? {
        if !config.caddy_enabled {
            continue;
        }

        let cert_path = certs_folder.join(format!("{}.test.pem", config.name));
        let key_path = certs_folder.join(format!("{}-key.pem", config.name));

        content.push_str(&format!("{} {{\n", config.domain));

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

    fs::write(&caddyfile, content)?;

    let caddy_running = std::process::Command::new("pgrep")
        .arg("-x")
        .arg("caddy")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    if caddy_running {
        let _ = run_shell(
            &apps_folder(),
            &format!("caddy reload --config '{}'", caddyfile.display()),
        );
    } else {
        let _ = run_shell(
            &apps_folder(),
            &format!("caddy start --config '{}'", caddyfile.display()),
        );
    }

    Ok(())
}

trait ExpandHome {
    fn expand_home(&self) -> PathBuf;
}

impl<T: AsRef<Path>> ExpandHome for T {
    fn expand_home(&self) -> PathBuf {
        let path = self.as_ref();
        if let Some(str_path) = path.to_str() {
            if str_path.starts_with('~') {
                if let Some(home) = dirs::home_dir() {
                    return PathBuf::from(str_path.replacen('~', home.to_str().unwrap(), 1));
                }
            }
        }
        path.to_path_buf()
    }
}
