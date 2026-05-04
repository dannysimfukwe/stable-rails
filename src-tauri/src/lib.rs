// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
use anyhow::Result;
use serde::{Deserialize, Serialize};
use tauri::menu::{Menu, MenuItem, Submenu};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager};

mod stable;

#[derive(Serialize)]
struct DoctorReport {
    report: String,
}

#[tauri::command]
fn list_apps() -> Result<Vec<stable::list::AppInfo>, String> {
    stable::list::run().map_err(|err| err.to_string())
}

#[tauri::command]
fn add_app(folder: String) -> Result<(), String> {
    stable::add::run(&folder).map_err(|err| err.to_string())
}

#[tauri::command]
fn remove_app(name: String) -> Result<(), String> {
    stable::remove::run(&name).map_err(|err| err.to_string())
}

#[derive(Clone, Serialize)]
struct ProgressEvent {
    message: String,
}

#[derive(Clone, Serialize)]
struct LogEvent {
    line: String,
}

#[tauri::command]
fn create_app(window: tauri::Window, name: String) -> Result<(), String> {
    let progress_window = window.clone();
    let log_window = window.clone();

    let progress = move |message: &str| {
        let _ = progress_window.emit(
            "stable:progress",
            ProgressEvent {
                message: message.to_string(),
            },
        );
    };
    let log_window2 = log_window.clone();
    let log = move |line: &str| {
        let _ = log_window.emit(
            "stable:log",
            LogEvent {
                line: line.to_string(),
            },
        );
    };

    std::thread::spawn(move || {
        if let Err(err) = stable::new::run_with_progress(&name, progress, log) {
            let _ = log_window2.emit(
                "stable:log",
                LogEvent {
                    line: format!("ERROR: {}", err),
                },
            );
        }
    });

    Ok(())
}

#[tauri::command]
fn start_app(name: String) -> Result<(), String> {
    stable::start::run(&name).map_err(|err| err.to_string())
}

#[tauri::command]
fn start_all_apps() {
    std::thread::spawn(|| {
        let _ = stable::start_all::run();
    });
}

#[tauri::command]
fn stop_app(name: String) -> Result<(), String> {
    stable::stop::run(&name).map_err(|err| err.to_string())
}

#[tauri::command]
fn stop_all_apps() {
    std::thread::spawn(|| {
        let _ = stable::stop_all::run();
    });
}

#[tauri::command]
fn restart_app(name: String) -> Result<(), String> {
    stable::restart::run(&name).map_err(|err| err.to_string())
}

#[tauri::command]
fn secure_app(domain: String) -> Result<(), String> {
    stable::secure::run(&domain).map_err(|err| err.to_string())
}

#[tauri::command]
fn doctor() -> Result<DoctorReport, String> {
    stable::doctor::run()
        .map(|report| DoctorReport { report })
        .map_err(|err| err.to_string())
}

#[tauri::command]
fn dependencies_status() -> Result<stable::doctor::DependenciesStatus, String> {
    Ok(stable::doctor::get_status())
}

#[tauri::command]
fn install_dependency(dep: String) -> Result<String, String> {
    match dep.as_str() {
        "caddy" => stable::doctor::install_caddy().map_err(|e| e.to_string()),
        "mkcert" => stable::doctor::install_mkcert().map_err(|e| e.to_string()),
        _ => Ok(format!("Unknown dependency: {}", dep)),
    }
}

#[tauri::command]
fn apps_folder() -> Result<String, String> {
    Ok(stable::utils::apps_folder().to_string_lossy().to_string())
}

#[tauri::command]
fn open_folder(path: String) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(&path)
        .spawn()
        .map_err(|err| err.to_string())?;
    Ok(())
}

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(|err| err.to_string())?;
    Ok(())
}

#[tauri::command]
async fn confirm_dialog(
    window: tauri::Window,
    title: String,
    message: String,
) -> Result<bool, String> {
    use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
    let dialog = window.dialog();
    Ok(dialog.message(message).title(title).buttons(MessageDialogButtons::YesNo).blocking_show())
}

#[tauri::command]
async fn pick_folder(_window: tauri::Window, title: String) -> Result<Option<String>, String> {
    let result = rfd::AsyncFileDialog::new().set_title(&title).pick_folder();
    let path = result.await.map(|p| p.path().to_string_lossy().to_string());
    Ok(path)
}

#[tauri::command]
fn load_app_config(name: String) -> Result<stable::config::AppConfig, String> {
    stable::config::load_app_config(&name).map_err(|err| err.to_string())
}

#[tauri::command]
fn rails_console(name: String, command: String) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let trimmed = command.trim().to_lowercase();
    if trimmed.starts_with("rails ") || trimmed == "c" || trimmed == "console" {
        let output = std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg(&format!(
                "cd '{}' && '{}' '{}' exec rails console",
                app_path.display(),
                ruby_path.display(),
                bundle_path.display()
            ))
            .output()
            .map_err(|e| e.to_string())?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        Ok(format!("{}{}", stdout, stderr))
    } else {
        let script_path = "/tmp/stable_console.rb";
        let command_trimmed = command.trim();

        let wrapped = if command_trimmed.starts_with("puts") || command_trimmed.starts_with("p ")
            || command_trimmed.starts_with("rails ")
            || command_trimmed.starts_with("bundle ")
            || command_trimmed.starts_with("rake ")
            || command_trimmed.starts_with("yarn ")
            || command_trimmed.starts_with("npm ")
            || command_trimmed.starts_with("ruby ")
            || command_trimmed.starts_with("gem ")
        {
            command_trimmed.to_string()
        } else if command_trimmed.starts_with("generate ") || command_trimmed.starts_with("g ") {
            format!("rails {}", command_trimmed)
        } else {
            format!("puts ({})", command)
        };

        std::fs::write(script_path, &wrapped).map_err(|e| e.to_string())?;

        let output = std::process::Command::new("/bin/zsh")
            .arg("-lc")
            .arg(&format!(
                "cd '{}' && '{}' '{}' exec rails runner -e development {}",
                app_path.display(),
                ruby_path.display(),
                bundle_path.display(),
                script_path
            ))
            .output()
            .map_err(|e| e.to_string())?;

        let _ = std::fs::remove_file(script_path).map_err(|e| e.to_string());

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        if !stderr.is_empty() && !stderr.contains("Booting") {
            Ok(format!("{}\n{}", stdout, stderr))
        } else {
            Ok(stdout)
        }
    }
}

#[tauri::command]
fn rails_command(name: String, command: String) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && '{}' '{}' exec {}",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display(),
            command
        ))
        .output()
        .map_err(|e| e.to_string())?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    Ok(format!("{}{}", stdout, stderr))
}

#[tauri::command]
fn db_tables(name: String) -> Result<Vec<String>, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(format!(
            "cd '{}' && '{}' '{}' exec rails runner 'ActiveRecord::Base.connection.tables.sort.each {{ |t| puts t }}'",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display()
        ))
        .output()
        .map_err(|err| err.to_string())?;

    let stderr = String::from_utf8_lossy(&output.stderr);
    if !stderr.is_empty() && !output.status.success() {
        return Err(stderr.to_string());
    }

    let tables = String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_string())
        .collect();
    Ok(tables)
}

#[derive(Serialize, Deserialize)]
struct QueryResult {
    columns: Vec<String>,
    rows: Vec<Vec<String>>,
}

#[tauri::command]
fn db_query(name: String, sql: String) -> Result<QueryResult, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let script_path = "/tmp/stable_query.rb";
    let sql_escaped = sql.replace('"', "\\\"");
    std::fs::write(
        script_path,
        format!(
            r#"require 'json'
adapter = ActiveRecord::Base.connection.adapter_name
sql = "{}"
table = if sql =~ /FROM\s+[`"']?(\w+)[`"']?/i
  $1.gsub(/[`"']/, '')
elsif sql =~ /UPDATE\s+[`"']?(\w+)[`"']?/i
  $1.gsub(/[`"']/, '')
elsif sql =~ /INTO\s+[`"']?(\w+)[`"']?/i
  $1.gsub(/[`"']/, '')
else
  sql.split(' ').first.to_s.gsub(/[`"']/, '')
end
cols = case
when adapter =~ /sqlite/i && !table.empty?
  ActiveRecord::Base.connection.execute("PRAGMA table_info(" + table + ")").to_a.map {{ |r| r["name"] }}
when adapter =~ /mysql/i && !table.empty?
  ActiveRecord::Base.connection.execute("DESCRIBE `" + table + "`").to_a.map {{ |r| r[0] }}
else
  []
end
result = ActiveRecord::Base.connection.execute("{}")
if result.respond_to?(:columns)
  cols = result.columns.map(&:name)
  rows = result.to_a.map {{ |row| cols.map {{ |c| row[c].to_s }} }}
else
  rows = result.to_a.map {{ |r| r.is_a?(Hash) ? cols.map {{ |c| r[c].to_s }} : r.map(&:to_s) }}
end
puts JSON.generate(columns: cols, rows: rows)
"#,
            sql_escaped, sql_escaped
        ),
    ).map_err(|e| e.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && '{}' '{}' exec rails runner {}",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display(),
            script_path
        ))
        .output()
        .map_err(|err| err.to_string())?;

    let _ = std::fs::remove_file(script_path).map_err(|e| e.to_string());

    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        return Err(if stderr.is_empty() { "Query failed".to_string() } else { stderr });
    }

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();

    if let Ok(parsed) = serde_json::from_str::<QueryResult>(&stdout) {
        return Ok(parsed);
    }

    Ok(QueryResult {
        columns: Vec::new(),
        rows: Vec::new(),
    })
}

#[tauri::command]
fn db_execute(name: String, sql: String) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let script_path = "/tmp/stable_exec.rb";
    let sql_escaped = sql.replace('"', "\\\"");
    let ruby_script = format!(
        r#"sql = "{}"
result = ActiveRecord::Base.connection.execute(sql)
puts result.inspect
"#,
        sql_escaped
    );
    std::fs::write(script_path, &ruby_script).map_err(|e| e.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && '{}' '{}' exec rails runner {}",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display(),
            script_path
        ))
        .output()
        .map_err(|err| err.to_string())?;

    let _ = std::fs::remove_file(script_path).map_err(|e| e.to_string());

    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return Err(if stderr.is_empty() { "Execution failed".to_string() } else { stderr });
    }

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(stdout)
}

#[tauri::command]
fn db_export(name: String, table: String, format: String) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let script_path = "/tmp/stable_export.rb";
    let table_escaped = table.replace('"', "\\\"");
    let ruby_script = format!(
        r#"require 'json'
require 'csv'
table_name = "{}"
rows = ActiveRecord::Base.connection.execute("SELECT * FROM " + table_name).to_a
cols = rows.first ? rows.first.keys : []
result = case "{}"
when 'json'
  JSON.generate(cols: cols, rows: rows.map do |r|
    cols.map do |c|
      r[c].to_s
    end
  end)
when 'csv'
  CSV.generate do |csv|
    csv << cols
    rows.each do |r|
      csv << cols.map do |c|
        r[c].to_s
      end
    end
  end
else
  "ERROR: Unknown format"
end
puts result
"#,
        table_escaped, format
    );
    std::fs::write(script_path, &ruby_script).map_err(|e| e.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && '{}' '{}' exec rails runner {}",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display(),
            script_path
        ))
        .output()
        .map_err(|err| err.to_string())?;

    let _ = std::fs::remove_file(script_path).map_err(|e| e.to_string());

    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() && stderr.contains("ERROR") {
        return Err(stderr);
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[tauri::command]
fn db_import(name: String, table: String, format: String, data: String) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    let script_path = "/tmp/stable_import.rb";
    let table_escaped = table.replace('"', "\\\"");
    let format_escaped = format.replace('"', "\\\"");
    let data_escaped = data.replace("\\", "\\\\").replace("\"", "\\\"");
    let ruby_script = format!(
        r#"require 'json'
require 'csv'
table_name = "{}"
format_type = "{}"
raw_data = "{}"
cols = nil
rows = nil
case format_type
when 'json'
  parsed = JSON.parse(raw_data)
  cols = parsed['columns']
  rows = parsed['rows']
when 'csv'
  parsed = CSV.parse(raw_data)
  cols = parsed.first
  rows = parsed[1..-1]
else
  puts "ERROR: Unknown format"
  exit 1
end
imported = 0
rows.each do |row|
  placeholders = (1..cols.length).map {{ |i| "?" }}.join(', ')
  cols_sql = cols.map {{ |c| "`" + c + "`" }}.join(', ')
  sql = "INSERT INTO " + table_name + " (" + cols_sql + ") VALUES (" + placeholders + ")"
  ActiveRecord::Base.connection.execute(sql, *row)
  imported += 1
end
puts "OK: " + imported.to_s + " rows imported"
"#,
        table_escaped, format_escaped, data_escaped
    );
    std::fs::write(script_path, &ruby_script).map_err(|e| e.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && '{}' '{}' exec rails runner {}",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display(),
            script_path
        ))
        .output()
        .map_err(|err| err.to_string())?;

    let _ = std::fs::remove_file(script_path).map_err(|e| e.to_string());

    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return Err(if stderr.is_empty() { "Import failed".to_string() } else { stderr });
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[tauri::command]
fn redis_scan(name: String, pattern: String) -> Result<Vec<String>, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;
    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && '{}' '{}' exec rails runner 'Redis.new.keys(\"{}\").sort.each {{ |k| puts k }}'",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display(),
            pattern
        ))
        .output()
        .map_err(|err| err.to_string())?;
    let keys = String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_string())
        .collect();
    Ok(keys)
}

#[tauri::command]
fn save_app_settings(
    name: String,
    railsEnv: String,
    port: i32,
    tlsEnabled: bool,
    caddyEnabled: bool,
) -> Result<(), String> {
    let mut config = stable::config::load_app_config(&name).map_err(|err| err.to_string())?;
    config.rails_env = railsEnv;
    config.port = port as u16;
    config.tls_enabled = tlsEnabled;
    config.caddy_enabled = caddyEnabled;
    stable::config::save_app_config(&config).map_err(|err| err.to_string())?;
    stable::config::update_caddyfile().map_err(|err| err.to_string())?;
    Ok(())
}

#[tauri::command]
fn bundle_install(name: String) -> Result<String, String> {
    let config = stable::config::load_app_config(&name).map_err(|err| err.to_string())?;
    let app_path = config.path;

    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|err| err.to_string())?;

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!(
            "cd '{}' && {} {} install",
            app_path.display(),
            ruby_path.display(),
            bundle_path.display()
        ))
        .output()
        .map_err(|err| err.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return Err(format!("Bundle install failed:\n{}", stderr));
    }
    Ok(stdout)
}

#[tauri::command]
fn get_env_file(name: String) -> Result<Vec<(String, String)>, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let env_path = app_path.join(".env");
    
    if !env_path.exists() {
        return Ok(Vec::new());
    }
    
    let content = std::fs::read_to_string(&env_path).map_err(|e| e.to_string())?;
    let mut vars = Vec::new();
    
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(pos) = line.find('=') {
            let key = line[..pos].trim().to_string();
            let value = line[pos + 1..].trim().to_string();
            vars.push((key, value));
        }
    }
    
    Ok(vars)
}

#[tauri::command]
fn save_env_file(name: String, vars: Vec<(String, String)>) -> Result<(), String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let env_path = app_path.join(".env");
    
    let mut content = String::new();
    for (key, value) in vars {
        content.push_str(&format!("{}={}\n", key, value));
    }
    
    std::fs::write(&env_path, content).map_err(|e| e.to_string())?;
    Ok(())
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct DeployConfig {
    server: String,
    ssh_user: String,
    registry: String,
    registry_username: String,
    #[serde(skip_serializing)]
    registry_password: String,
    app_name: String,
    domain: Option<String>,
    #[serde(skip_serializing)]
    rails_master_key: String,
}

#[derive(Debug, serde::Serialize)]
struct DeployConfigResponse {
    configured: bool,
    config: Option<DeployConfig>,
}

#[tauri::command]
fn get_deploy_config(name: String) -> Result<DeployConfigResponse, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let deploy_yml = app_path.join("config/deploy.yml");
    
    if !deploy_yml.exists() {
        return Ok(DeployConfigResponse {
            configured: false,
            config: None,
        });
    }
    
    let content = std::fs::read_to_string(&deploy_yml).map_err(|e| e.to_string())?;
    
    // Parse the YAML to extract config
    let docs = yaml_rust::YamlLoader::load_from_str(&content).map_err(|e| e.to_string())?;
    if docs.is_empty() {
        return Ok(DeployConfigResponse {
            configured: false,
            config: None,
        });
    }
    
    let doc = &docs[0];
    
    let service = doc["service"].as_str().unwrap_or(&name).to_string();
    
    // Extract server from servers.web array
    let server = doc["servers"]["web"]
        .as_vec()
        .and_then(|v| v.first())
        .and_then(|y| y.as_str())
        .unwrap_or("")
        .to_string();
    
    // Extract SSH user from server string (e.g., "root@123.456.789.0" or just "123.456.789.0")
    let (ssh_user, server_host) = if server.contains('@') {
        let parts: Vec<&str> = server.split('@').collect();
        (parts[0].to_string(), parts[1].to_string())
    } else {
        ("root".to_string(), server)
    };
    
    // Extract registry username
    let registry_username = doc["registry"]["username"]
        .as_str()
        .unwrap_or("")
        .to_string();
    
    // Extract image to determine registry
    let image = doc["image"].as_str().unwrap_or("").to_string();
    let registry = if image.starts_with("ghcr.io/") {
        "GitHub Container Registry".to_string()
    } else if image.starts_with("registry.gitlab.com/") {
        "GitLab Container Registry".to_string()
    } else {
        "Docker Hub".to_string()
    };
    
    // Extract domain from proxy settings if present
    let domain = doc["proxy"]["host"]
        .as_str()
        .map(|s| s.to_string());
    
    // Read secrets file for sensitive values
    let secrets_path = app_path.join(".kamal/secrets");
    let mut registry_password = String::new();
    let mut rails_master_key = String::new();
    
    if secrets_path.exists() {
        if let Ok(secrets_content) = std::fs::read_to_string(&secrets_path) {
            for line in secrets_content.lines() {
                let line = line.trim();
                if line.starts_with("export KAMAL_REGISTRY_PASSWORD=") {
                    registry_password = line["export KAMAL_REGISTRY_PASSWORD=".len()..]
                        .trim_matches('"')
                        .to_string();
                }
                if line.starts_with("export RAILS_MASTER_KEY=") {
                    rails_master_key = line["export RAILS_MASTER_KEY=".len()..]
                        .trim_matches('"')
                        .to_string();
                }
            }
        }
    }
    
    Ok(DeployConfigResponse {
        configured: !server_host.is_empty(),
        config: Some(DeployConfig {
            server: server_host,
            ssh_user,
            registry,
            registry_username,
            registry_password,
            app_name: service,
            domain,
            rails_master_key,
        }),
    })
}

#[tauri::command]
fn save_deploy_config(name: String, config: DeployConfig) -> Result<(), String> {
    let app_path = stable::utils::apps_folder().join(&name);
    
    // Validate required fields
    if config.server.trim().is_empty() {
        return Err("Server IP or hostname is required".to_string());
    }
    if config.registry_username.trim().is_empty() {
        return Err("Registry username is required".to_string());
    }
    if config.registry_password.trim().is_empty() {
        return Err("Registry password is required".to_string());
    }
    if config.rails_master_key.trim().is_empty() {
        return Err("Rails Master Key is required".to_string());
    }
    
    let app_name = if config.app_name.trim().is_empty() {
        name.clone()
    } else {
        config.app_name.trim().to_string()
    };
    
    // Build server string with SSH user
    let server_str = if config.ssh_user == "root" {
        config.server.trim().to_string()
    } else {
        format!("{}@{}", config.ssh_user.trim(), config.server.trim())
    };
    
    // Build image string based on registry
    let image = match config.registry.as_str() {
        "GitHub Container Registry" => format!("ghcr.io/{}/{}", config.registry_username.trim(), app_name),
        "GitLab Container Registry" => format!("registry.gitlab.com/{}/{}", config.registry_username.trim(), app_name),
        _ => format!("{}/{}", config.registry_username.trim(), app_name),
    };
    
    // Generate deploy.yml
    let mut deploy_yaml = format!("service: {}\n", app_name);
    deploy_yaml.push_str(&format!("image: {}\n", image));
    deploy_yaml.push_str("servers:\n");
    deploy_yaml.push_str("  web:\n");
    deploy_yaml.push_str(&format!("    - {}\n", server_str));
    deploy_yaml.push_str("registry:\n");
    deploy_yaml.push_str(&format!("  username: {}\n", config.registry_username.trim()));
    deploy_yaml.push_str("  password:\n");
    deploy_yaml.push_str("    - KAMAL_REGISTRY_PASSWORD\n");
    
    // Add proxy/domain if provided
    if let Some(domain) = &config.domain {
        if !domain.trim().is_empty() {
            deploy_yaml.push_str("proxy:\n");
            deploy_yaml.push_str(&format!("  host: {}\n", domain.trim()));
        }
    }
    
    deploy_yaml.push_str("env:\n");
    deploy_yaml.push_str("  secret:\n");
    deploy_yaml.push_str("    - RAILS_MASTER_KEY\n");
    
    // Ensure config directory exists
    let config_dir = app_path.join("config");
    std::fs::create_dir_all(&config_dir).map_err(|e| e.to_string())?;
    
    // Write deploy.yml
    std::fs::write(config_dir.join("deploy.yml"), deploy_yaml)
        .map_err(|e| format!("Failed to write deploy.yml: {}", e))?;
    
    // Write .kamal/secrets
    let kamal_dir = app_path.join(".kamal");
    std::fs::create_dir_all(&kamal_dir).map_err(|e| e.to_string())?;
    
    let secrets_content = format!(
        "#!/bin/bash\nexport KAMAL_REGISTRY_PASSWORD=\"{}\"\nexport RAILS_MASTER_KEY=\"{}\"\n",
        config.registry_password.replace("\"", "\\\""),
        config.rails_master_key.replace("\"", "\\\"")
    );
    
    let secrets_path = kamal_dir.join("secrets");
    std::fs::write(&secrets_path, secrets_content)
        .map_err(|e| format!("Failed to write secrets file: {}", e))?;
    
    // Make secrets executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&secrets_path).map_err(|e| e.to_string())?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&secrets_path, perms).map_err(|e| e.to_string())?;
    }
    
    Ok(())
}

#[tauri::command]
fn check_kamal(name: String) -> Result<KamalStatus, String> {
    let app_path = stable::utils::apps_folder().join(&name);

    let has_config = app_path.join("config/deploy.yml").exists();
    
    // Check if kamal is in the Gemfile (more reliable than bundle exec)
    let gemfile_path = app_path.join("Gemfile");
    let gemfile_lock = app_path.join("Gemfile.lock");
    let mut kamal_in_gemfile = false;
    
    if gemfile_path.exists() {
        if let Ok(content) = std::fs::read_to_string(&gemfile_path) {
            kamal_in_gemfile = content.contains("kamal");
        }
    }
    
    // Also check Gemfile.lock for kamal
    if !kamal_in_gemfile && gemfile_lock.exists() {
        if let Ok(content) = std::fs::read_to_string(&gemfile_lock) {
            kamal_in_gemfile = content.contains("kamal (");
        }
    }
    
    let path = format!(
        "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:{}",
        std::env::var("PATH").unwrap_or_default()
    );
    let docker_installed = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&format!("export PATH='{}' && which docker", path))
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    
    Ok(KamalStatus {
        kamal_installed: kamal_in_gemfile,
        has_config,
        docker_installed,
        app_name: name,
    })
}

#[tauri::command]
fn kamal_command(name: String, cmd: String) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let (ruby_path, bundle_path) =
        stable::ruby_manager::ensure_ruby_for_app(&app_path).map_err(|e| e.to_string())?;

    // Source .kamal/secrets if it exists to load registry password and master key
    let secrets_source = if app_path.join(".kamal/secrets").exists() {
        format!("source '{}/.kamal/secrets' && ", app_path.display())
    } else {
        String::new()
    };

    // Use the exact ruby and bundle paths to avoid version mismatches
    let full_cmd = format!(
        "cd '{}' && {}'{}' '{}' exec kamal {}",
        app_path.display(),
        secrets_source,
        ruby_path.display(),
        bundle_path.display(),
        cmd
    );

    let output = std::process::Command::new("/bin/zsh")
        .arg("-lc")
        .arg(&full_cmd)
        .stdin(std::process::Stdio::null())
        .output()
        .map_err(|err| err.to_string())?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    
    if !output.status.success() {
        let error_msg = if stderr.is_empty() { stdout } else { stderr };
        
        // Check for remote Docker not found (Kamal SSHing to server without Docker)
        if error_msg.contains("docker: not found") && error_msg.contains("Pseudo-terminal") {
            return Err(format!(
                "Docker is not installed on the remote deployment server.\n\n\
                Run 'Kamal Setup' first to install Docker on your server, then try deploying.\n\n\
                Original error:\n{}",
                error_msg
            ));
        }
        
        // Check for remote Docker not found (without SSH message)
        if error_msg.contains("docker: not found") {
            return Err(format!(
                "Docker is not found on the target server. If this is a remote deployment, run 'Kamal Setup' first.\n\n\
                If deploying locally, make sure Docker is installed and running:\n  brew install docker\n\n\
                Original error:\n{}",
                error_msg
            ));
        }
        
        // Check for SSH connection issues
        if error_msg.contains("Pseudo-terminal will not be allocated") {
            return Err(format!(
                "Could not connect to the remote server via SSH.\n\n\
                Make sure your server is configured correctly in config/deploy.yml and is accessible.\n\n\
                Original error:\n{}",
                error_msg
            ));
        }
        
        // Check for invalid Kamal command
        if error_msg.contains("Could not find command") {
            return Err(format!(
                "'kamal {}' is not a valid command in your version of Kamal.\n\n\
                Common Kamal commands:\n  kamal setup    - Install Docker on remote server\n  kamal deploy   - Deploy the application\n  kamal logs     - Show application logs\n  kamal remove   - Remove the application\n\n\
                Original error:\n{}",
                cmd, error_msg
            ));
        }
        
        // Check for actual Bundler compatibility errors (GemParser, uninitialized constant, etc.)
        if error_msg.contains("GemParser") || error_msg.contains("uninitialized constant") || error_msg.contains("LoadError") {
            return Err(format!("Bundler compatibility error. Run this in your app directory:\n\ncd {}\ngem update --system\n# or\ngem install bundler --version '~> 2.0'\n\nThen try again.\n\nOriginal error:\n{}", app_path.display(), error_msg));
        }
        // Check if kamal is just not installed
        if error_msg.contains("command not found: kamal") || error_msg.contains("Could not find gem 'kamal'") {
            return Err(format!("Kamal gem not installed. Make sure kamal is in your Gemfile and run 'bundle install' in your app directory.\n\nOriginal error:\n{}", error_msg));
        }
        return Err(format!("{}", error_msg));
    }
    
    Ok(if stdout.is_empty() { stderr } else { stdout })
}

#[derive(Debug, serde::Serialize)]
struct KamalStatus {
    kamal_installed: bool,
    has_config: bool,
    docker_installed: bool,
    app_name: String,
}

#[tauri::command]
fn list_ruby_versions() -> Result<Vec<String>, String> {
    let mut versions = Vec::new();

    let local_dir = stable::ruby_manager::ruby_versions_dir();
    if local_dir.exists() {
        for entry in std::fs::read_dir(&local_dir).map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("ruby-") {
                let v = name.strip_prefix("ruby-").unwrap().to_string();
                if !versions.contains(&v) {
                    versions.push(v);
                }
            }
        }
    }

    let homebrew_prefix = std::process::Command::new("brew")
        .arg("--prefix")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "/opt/homebrew".to_string());

    for v in &["3.4", "3.3", "3.2", "3.1"] {
        let brew_path = format!("{}/opt/ruby@{}/bin/ruby", homebrew_prefix, v);
        if std::path::Path::new(&brew_path).exists() && !versions.contains(&v.to_string()) {
            versions.push(v.to_string());
        }
    }

    if let Some(home_dir) = dirs::home_dir() {
        let rvm_rubies = home_dir.join(".rvm/rubies");
        if rvm_rubies.exists() {
            for entry in std::fs::read_dir(&rvm_rubies).map_err(|e| e.to_string())? {
                let entry = entry.map_err(|e| e.to_string())?;
                let name = entry.file_name().to_string_lossy().to_string();

                if name.starts_with("ruby-") && entry.path().is_dir() {
                    let ruby_bin = entry.path().join("bin").join("ruby");
                    if ruby_bin.exists() {
                        let version_str = name.strip_prefix("ruby-").unwrap_or(&name).to_string();
                        let short_version = extract_short_version(&version_str);
                        if !versions.contains(&version_str) && !versions.contains(&short_version) {
                            versions.push(short_version);
                        }
                    }
                }
            }
        }
    }

    versions.sort();
    versions.dedup();
    Ok(versions)
}

fn extract_short_version(full: &str) -> String {
    let parts: Vec<&str> = full.split('.').collect();
    if parts.len() >= 2 {
        format!("{}.{}", parts[0], parts[1])
    } else {
        full.to_string()
    }
}

#[tauri::command]
fn get_app_logs(name: String, lines: i32) -> Result<String, String> {
    let app_path = stable::utils::apps_folder().join(&name);
    let log_path = app_path.join("log").join("development.log");
    let prod_log_path = app_path.join("log").join("production.log");

    let log_file = if prod_log_path.exists() {
        prod_log_path
    } else if log_path.exists() {
        log_path
    } else {
        return Ok("No log file found. Check the app's log/ directory.".to_string());
    };

    let content = std::fs::read_to_string(&log_file).map_err(|e| e.to_string())?;
    
    let all_lines: Vec<&str> = content.lines().collect();
    let start = if all_lines.len() > lines as usize {
        all_lines.len() - lines as usize
    } else {
        0
    };
    
    let tail_lines = &all_lines[start..];
    Ok(tail_lines.join("\n"))
}

#[tauri::command]
fn install_ruby(version: String) -> Result<String, String> {
    stable::ruby_manager::install_ruby_version(&version)
        .map(|_v| format!("Ruby {} installed", version))
        .map_err(|e| e.to_string())
}

fn open_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let handle = app.handle();
            let show_item = MenuItem::new(app, "Show Stable", true, None::<&str>)?;
            let about_item = MenuItem::new(app, "About Stable", true, None::<&str>)?;
            let quit_item = MenuItem::new(app, "Quit", true, None::<&str>)?;
            let tray_menu = Menu::with_items(app, &[&show_item, &about_item, &quit_item])?;

            let tray_handle = handle.clone();
            let mut tray_builder = TrayIconBuilder::new()
                .menu(&tray_menu)
                .tooltip("Stable")
                .on_menu_event(move |tray, event| match event.id().as_ref() {
                    "Show Stable" => open_main_window(tray.app_handle()),
                    "About Stable" => {
                        let _ = tray.app_handle().emit("show-about", ());
                    }
                    "Quit" => tray.app_handle().exit(0),
                    _ => {}
                })
                .on_tray_icon_event(move |tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        open_main_window(tray.app_handle());
                    }
                });

            let _tray = tray_builder.build(&tray_handle)?;

            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_skip_taskbar(true);
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            list_apps,
            add_app,
            remove_app,
            create_app,
            start_app,
            start_all_apps,
            stop_app,
            stop_all_apps,
            restart_app,
            secure_app,
            doctor,
            dependencies_status,
            install_dependency,
            apps_folder,
            open_folder,
            open_url,
            confirm_dialog,
            pick_folder,
            load_app_config,
            rails_console,
            rails_command,
            db_tables,
            db_query,
            db_execute,
            db_export,
            db_import,
            redis_scan,
            get_app_logs,
            save_app_settings,
            bundle_install,
            list_ruby_versions,
            install_ruby,
            get_env_file,
            save_env_file,
            check_kamal,
            kamal_command,
            get_deploy_config,
            save_deploy_config
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
