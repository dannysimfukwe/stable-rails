// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
use anyhow::Result;
use serde::{Deserialize, Serialize};
use tauri::menu::{Menu, MenuItem};
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

    let script_path = "/tmp/stable_console.rb";
    let wrapped_command = if command.trim().starts_with("puts") || command.trim().starts_with("p ") {
        command.clone()
    } else {
        format!("puts ({})", command)
    };
    std::fs::write(script_path, &wrapped_command).map_err(|e| e.to_string())?;

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
            let quit_item = MenuItem::new(app, "Quit", true, None::<&str>)?;
            let tray_menu = Menu::with_items(app, &[&show_item, &quit_item])?;

            let tray_handle = handle.clone();
            let mut tray_builder = TrayIconBuilder::new()
                .menu(&tray_menu)
                .on_menu_event(move |tray, event| match event.id().as_ref() {
                    "Show Stable" => open_main_window(tray.app_handle()),
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

            if let Some(icon) = app.default_window_icon().cloned() {
                tray_builder = tray_builder.icon(icon);
            }

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
            apps_folder,
            open_folder,
            open_url,
            confirm_dialog,
            pick_folder,
            load_app_config,
            rails_console,
            db_tables,
            db_query,
            redis_scan,
            save_app_settings,
            bundle_install,
            list_ruby_versions,
            install_ruby
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
