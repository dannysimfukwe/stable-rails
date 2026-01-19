use anyhow::Result;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use yaml_rust::{Yaml, YamlLoader};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppConfig {
    pub name: String,
    pub port: u16,
    pub ruby_version: Option<String>,
    pub rails_version: Option<String>,
    pub rails_env: String,
    pub tls_enabled: bool,
    pub caddy_enabled: bool,
    pub domain: String,
    pub custom_domain: Option<String>,
    pub pid: Option<i32>,
    pub time_started: Option<i64>,
}

impl Default for AppConfig {
    fn default() -> Self {
        AppConfig {
            name: String::new(),
            port: 3000,
            ruby_version: None,
            rails_version: None,
            rails_env: "development".to_string(),
            tls_enabled: true,
            caddy_enabled: true,
            domain: String::new(),
            custom_domain: None,
            pid: None,
            time_started: None,
        }
    }
}

pub fn config_folder() -> PathBuf {
    apps_folder().join(".stable")
}

pub fn apps_folder() -> PathBuf {
    Path::new("~/.stable_apps").expand_home().to_path_buf()
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

fn global_config_path() -> PathBuf {
    config_folder().join("config.yaml")
}

fn load_yaml_file(path: &Path) -> Option<Yaml> {
    if !path.exists() {
        return None;
    }
    match fs::read_to_string(path) {
        Ok(content) => {
            let docs = YamlLoader::load_from_str(&content).ok();
            docs.and_then(|d| d.get(0).cloned())
        }
        Err(_) => None,
    }
}

pub fn get_next_available_port() -> Result<u16> {
    let mut next_port: u16 = 3000;

    if let Some(config) = load_yaml_file(&global_config_path()) {
        if let Some(port) = config["next_port"].as_i64() {
            next_port = port as u16;
        }
    }

    // Check if port is in use
    while is_port_in_use(next_port) {
        next_port += 1;
    }

    // Update next port for next app
    let config_folder = config_folder();
    fs::create_dir_all(&config_folder)?;

    let config_path = global_config_path();
    let mut content = String::new();
    if config_path.exists() {
        content = fs::read_to_string(&config_path)?;
    }

    let new_next_port = next_port + 1;
    if content.contains("next_port:") {
        content = content.replace(
            regex::Regex::new(r"next_port:\s*\d+")
                .unwrap()
                .find(&content)
                .unwrap()
                .as_str(),
            &format!("next_port: {}", new_next_port),
        );
    } else {
        content.push_str(&format!("next_port: {}\n", new_next_port));
    }

    fs::write(&config_path, content)?;

    Ok(next_port)
}

fn is_port_in_use(port: u16) -> bool {
    use std::net::TcpListener;
    TcpListener::bind(("127.0.0.1", port)).is_err()
}

pub fn load_app_config(app_name: &str) -> Result<AppConfig> {
    let app_config_path = apps_folder().join(app_name).join(".stable.yaml");

    let mut app_config = AppConfig::default();
    app_config.name = app_name.to_string();
    app_config.domain = format!("{}.test", app_name);

    if let Some(config) = load_yaml_file(&app_config_path) {
        if let Some(port) = config["port"].as_i64() {
            app_config.port = port as u16;
        }
        if let Some(ruby) = config["ruby_version"].as_str() {
            app_config.ruby_version = Some(ruby.to_string());
        }
        if let Some(rails) = config["rails_version"].as_str() {
            app_config.rails_version = Some(rails.to_string());
        }
        if let Some(env) = config["rails_env"].as_str() {
            app_config.rails_env = env.to_string();
        }
        if let Some(tls) = config["tls_enabled"].as_bool() {
            app_config.tls_enabled = tls;
        }
        if let Some(caddy) = config["caddy_enabled"].as_bool() {
            app_config.caddy_enabled = caddy;
        }
        if let Some(domain) = config["custom_domain"].as_str() {
            app_config.custom_domain = Some(domain.to_string());
            app_config.domain = domain.to_string();
        }
        if let Some(pid) = config["pid"].as_i64() {
            app_config.pid = Some(pid as i32);
        }
        if let Some(ts) = config["time_started"].as_i64() {
            app_config.time_started = Some(ts);
        }
    }

    Ok(app_config)
}

pub fn save_app_config(app_name: &str, config: &AppConfig) -> Result<()> {
    let app_folder = apps_folder().join(app_name);
    fs::create_dir_all(&app_folder)?;

    let config_path = app_folder.join(".stable.yaml");
    let mut file = File::create(&config_path)?;

    writeln!(file, "name: {}", config.name)?;
    writeln!(file, "port: {}", config.port)?;
    if let Some(ruby) = &config.ruby_version {
        writeln!(file, "ruby_version: {}", ruby)?;
    }
    if let Some(rails) = &config.rails_version {
        writeln!(file, "rails_version: {}", rails)?;
    }
    writeln!(file, "rails_env: {}", config.rails_env)?;
    writeln!(file, "tls_enabled: {}", config.tls_enabled)?;
    writeln!(file, "caddy_enabled: {}", config.caddy_enabled)?;
    writeln!(file, "domain: {}", config.domain)?;
    if let Some(domain) = &config.custom_domain {
        writeln!(file, "custom_domain: {}", domain)?;
    }
    if let Some(pid) = config.pid {
        writeln!(file, "pid: {}", pid)?;
    }
    if let Some(ts) = config.time_started {
        writeln!(file, "time_started: {}", ts)?;
    }

    Ok(())
}

pub fn find_available_port_for_app(app_name: &str) -> Result<u16> {
    // First try to load existing config
    if let Ok(config) = load_app_config(app_name) {
        if config.port > 0 {
            return Ok(config.port);
        }
    }

    // Get next available port
    get_next_available_port()
}

pub fn delete_app_config(app_name: &str) -> Result<()> {
    let config_path = apps_folder().join(app_name).join(".stable.yaml");
    if config_path.exists() {
        fs::remove_file(&config_path)?;
    }
    Ok(())
}

pub fn load_all_app_configs() -> Result<Vec<AppConfig>> {
    let apps_root = apps_folder();
    if !apps_root.exists() {
        return Ok(Vec::new());
    }

    let mut configs = Vec::new();

    for entry in fs::read_dir(&apps_root)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            let app_name = entry.file_name().to_string_lossy().to_string();
            if let Ok(config) = load_app_config(&app_name) {
                configs.push(config);
            }
        }
    }

    Ok(configs)
}

pub fn update_global_caddyfile() -> Result<()> {
    use crate::stable::utils::run_shell;

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

    std::fs::write(&global_caddyfile, content)?;

    let reload_result = run_shell(
        &apps_folder(),
        &format!("caddy reload --config '{}'", global_caddyfile.display()),
    );

    if reload_result.is_err() {
        let _ = run_shell(
            &apps_folder(),
            &format!("caddy start --config '{}'", global_caddyfile.display()),
        );
    }

    Ok(())
}
