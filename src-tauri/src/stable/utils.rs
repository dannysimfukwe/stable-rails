use anyhow::Result;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Output};

/// Returns the folder where Rails apps are stored
pub fn apps_folder() -> PathBuf {
    Path::new("~/StableCaddy/projects").expanduser()
}

/// Runs a command and returns a Child
pub fn run_command<C: AsRef<str>>(cwd: C, program: &str, args: &[&str]) -> Result<Child> {
    let child = Command::new(program)
        .args(args)
        .current_dir(cwd.as_ref())
        .spawn()?;
    Ok(child)
}

/// Load all apps (by folder name)
pub fn load_apps() -> Result<Vec<String>> {
    let folder = apps_folder();
    if !folder.exists() {
        fs::create_dir_all(&folder)?;
    }
    let apps: Vec<String> = fs::read_dir(&folder)?
        .filter_map(|entry| entry.ok())
        .filter(|e| e.path().is_dir())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    Ok(apps)
}

/// Run a command in a login shell (helps GUI apps find PATH).
pub fn run_shell(cwd: &Path, command: &str) -> Result<ExitStatus> {
    let status = Command::new("/bin/zsh")
        .arg("-lc")
        .arg(command)
        .current_dir(cwd)
        .status()?;
    Ok(status)
}

pub fn run_shell_output(cwd: &Path, command: &str) -> Result<Output> {
    let output = Command::new("/bin/zsh")
        .arg("-lc")
        .arg(command)
        .current_dir(cwd)
        .output()?;
    Ok(output)
}

pub fn run_shell_spawn(cwd: &Path, command: &str) -> Result<Child> {
    let child = Command::new("/bin/zsh")
        .arg("-lc")
        .arg(command)
        .current_dir(cwd)
        .spawn()?;
    Ok(child)
}

pub fn ensure_hosts_entry(domain: &str) -> Result<bool> {
    let hosts_contents = fs::read_to_string("/etc/hosts").unwrap_or_default();
    if hosts_contents.contains(domain) {
        return Ok(false);
    }

    let command = format!(
        "printf \"\\n127.0.0.1\\t%s\\n\" \"{}\" | /usr/bin/tee -a /etc/hosts >/dev/null",
        domain
    );

    let script = format!(
        "osascript -e 'do shell script \"{}\" with administrator privileges'",
        command.replace('"', "\\\"")
    );
    let status = run_shell_output(Path::new("/"), &script)?;
    Ok(status.status.success())
}

pub fn shell_escape(value: &str) -> String {
    value.replace('"', "\\\"")
}

pub fn slugify_name(value: &str) -> String {
    let mut slug = String::new();
    let mut last_dash = false;
    for ch in value.chars() {
        let lower = ch.to_ascii_lowercase();
        if lower.is_ascii_alphanumeric() {
            slug.push(lower);
            last_dash = false;
        } else if !last_dash {
            slug.push('-');
            last_dash = true;
        }
    }
    let trimmed = slug.trim_matches('-').to_string();
    if trimmed.is_empty() {
        "app".to_string()
    } else {
        trimmed
    }
}

/// Helper: convert "~" in paths to home dir
trait ExpandUser {
    fn expanduser(&self) -> std::path::PathBuf;
}

impl ExpandUser for &Path {
    fn expanduser(&self) -> std::path::PathBuf {
        if let Some(str_path) = self.to_str() {
            if str_path.starts_with('~') {
                if let Some(home) = dirs::home_dir() {
                    return PathBuf::from(str_path.replacen('~', home.to_str().unwrap(), 1));
                }
            }
        }
        self.to_path_buf()
    }
}
