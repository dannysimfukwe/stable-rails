// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
use anyhow::Result;
use serde::Serialize;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager};

mod stable;

#[derive(Serialize)]
struct AppEntry {
    name: String,
    url: String,
}

#[derive(Serialize)]
struct DoctorReport {
    report: String,
}

#[tauri::command]
fn list_apps() -> Result<Vec<AppEntry>, String> {
    stable::list::run()
        .map(|apps| {
            apps.into_iter()
                .map(|name| AppEntry {
                    url: format!("https://{}.test", name),
                    name,
                })
                .collect()
        })
        .map_err(|err| err.to_string())
}

#[tauri::command]
fn add_app(folder: String) -> Result<(), String> {
    stable::add::run(&folder).map_err(|err| err.to_string())
}

#[tauri::command]
fn remove_app(name: String) -> Result<(), String> {
    eprintln!("DEBUG remove_app called with name: {}", name);
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
    let log = move |line: &str| {
        let _ = log_window.emit(
            "stable:log",
            LogEvent {
                line: line.to_string(),
            },
        );
    };

    stable::new::run_with_progress(&name, progress, log).map_err(|err| err.to_string())
}

#[tauri::command]
fn start_app(name: String) -> Result<(), String> {
    stable::start::run(&name).map_err(|err| err.to_string())
}

#[tauri::command]
fn stop_app(name: String) -> Result<(), String> {
    stable::stop::run(&name).map_err(|err| err.to_string())
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
    eprintln!("DEBUG open_url called with: {}", url);
    std::process::Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(|err| err.to_string())?;
    Ok(())
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
            stop_app,
            restart_app,
            secure_app,
            doctor,
            apps_folder,
            open_folder,
            open_url
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
