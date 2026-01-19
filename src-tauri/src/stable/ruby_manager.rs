use anyhow::Result;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const RUBY_VERSIONS_DIR: &str = "~/Library/Application Support/com.stable-desktop/ruby";

pub fn ruby_versions_dir() -> PathBuf {
    expand_home(RUBY_VERSIONS_DIR)
}

pub fn ruby_path_for_version(version: &str) -> PathBuf {
    ruby_versions_dir()
        .join(format!("ruby-{}", version))
        .join("bin")
        .join("ruby")
}

pub fn bundle_path_for_version(version: &str) -> PathBuf {
    ruby_versions_dir()
        .join(format!("ruby-{}", version))
        .join("bin")
        .join("bundle")
}

pub fn gem_home_for_version(version: &str) -> PathBuf {
    ruby_versions_dir()
        .join(format!("ruby-{}", version))
        .join("gems")
}

fn get_homebrew_prefix() -> String {
    std::process::Command::new("brew")
        .arg("--prefix")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "/opt/homebrew".to_string())
}

fn find_rvm_ruby_path(version: &str) -> Option<PathBuf> {
    let rvm_rubies = dirs::home_dir()?.join(".rvm/rubies");
    if !rvm_rubies.exists() {
        return None;
    }

    for entry in std::fs::read_dir(&rvm_rubies).ok()? {
        let entry = entry.ok()?;
        let name = entry.file_name().to_string_lossy().to_string();

        if name.starts_with("ruby-") && entry.path().is_dir() {
            let ruby_bin = entry.path().join("bin").join("ruby");
            if ruby_bin.exists() {
                if version_matches(&name, version) {
                    return Some(ruby_bin);
                }
            }
        }
    }
    None
}

fn version_matches(rvm_name: &str, requested: &str) -> bool {
    let rvm_version = rvm_name.strip_prefix("ruby-").unwrap_or(rvm_name);
    if rvm_version == requested {
        return true;
    }
    let requested_major_minor = if requested.contains('.') {
        let parts: Vec<&str> = requested.split('.').collect();
        if parts.len() >= 2 {
            Some(format!("{}.{}", parts[0], parts[1]))
        } else {
            None
        }
    } else {
        Some(requested.to_string())
    };

    if let Some(major_minor) = requested_major_minor {
        rvm_version.starts_with(&major_minor)
            && rvm_version.chars().nth(major_minor.len()) == Some('.')
    } else {
        false
    }
}

fn find_rvm_bundle_path(ruby_path: &Path) -> PathBuf {
    ruby_path.with_file_name("bundle")
}

fn is_homebrew_ruby_installed(version: &str) -> bool {
    let brew_prefix = get_homebrew_prefix();
    let brew_ruby = format!("{}/opt/ruby@{}/bin/ruby", brew_prefix, version);
    std::path::Path::new(&brew_ruby).exists()
}

pub fn is_ruby_installed(version: &str) -> bool {
    let clean_version = version.strip_prefix("ruby-").unwrap_or(version);
    let local_ruby = ruby_path_for_version(clean_version);
    if local_ruby.exists()
        && local_ruby
            .metadata()
            .map(|m| m.len() > 1000000)
            .unwrap_or(false)
    {
        return true;
    }
    if is_homebrew_ruby_installed(clean_version) {
        return true;
    }
    find_rvm_ruby_path(clean_version).is_some()
}

pub fn get_app_ruby_version(app_path: &Path) -> Option<String> {
    let ruby_version_path = app_path.join(".ruby-version");
    if ruby_version_path.exists() {
        if let Ok(content) = fs::read_to_string(&ruby_version_path) {
            let version = content.trim().to_string();
            let version = version.strip_prefix("ruby-").unwrap_or(&version).to_string();
            return Some(version);
        }
    }
    None
}

pub fn install_ruby_version(version: &str) -> Result<()> {
    let clean_version = version.strip_prefix("ruby-").unwrap_or(version);
    let ruby_dir = ruby_versions_dir().join(format!("ruby-{}", clean_version));
    let ruby_bin = ruby_dir.join("bin").join("ruby");

    if ruby_bin.exists()
        && ruby_bin
            .metadata()
            .map(|m| m.len() > 1000000)
            .unwrap_or(false)
    {
        return Ok(());
    }

    if is_homebrew_ruby_installed(version) {
        let brew_prefix = get_homebrew_prefix();
        let status = Command::new("/bin/bash")
            .arg("-c")
            .arg(format!(
                "cp -r {}/opt/ruby@{}/* {}/",
                brew_prefix,
                version,
                ruby_dir.display()
            ))
            .status()?;
        if status.success() {
            return Ok(());
        }
    }

    let status = Command::new("/bin/bash")
        .arg("-c")
        .arg(format!(
            "cd /tmp && rm -rf ruby-{} && curl -fsSL https://cache.ruby-lang.org/pub/ruby/{}/ruby-{}.tar.gz | tar xz && cd ruby-{} && ./configure --prefix={} --disable-install-doc --with-out-ext=fiddle,dbm,gdbm,sdbm,tk,win32ole && make -j$(sysctl -n hw.ncpu) && make install",
            clean_version, clean_version, clean_version, clean_version, ruby_dir.display()
        ))
        .status()?;

    if !status.success() {
        anyhow::bail!(
            "Failed to install Ruby {}.\n\nTry: brew install ruby@{}",
            clean_version,
            clean_version
        );
    }

    Ok(())
}

pub fn ensure_ruby_for_app(app_path: &Path) -> Result<(PathBuf, PathBuf)> {
    let version = get_app_ruby_version(app_path).unwrap_or_else(|| "3.4".to_string());

    if !is_ruby_installed(&version) {
        install_ruby_version(&version)?;
    }

    get_ruby_paths(&version)
}

fn get_ruby_paths(version: &str) -> Result<(PathBuf, PathBuf)> {
    let clean_version = version.strip_prefix("ruby-").unwrap_or(version);
    let local_ruby = ruby_path_for_version(clean_version);
    let local_bundle = bundle_path_for_version(clean_version);

    if local_ruby.exists() {
        return Ok((local_ruby, local_bundle));
    }

    let brew_prefix = get_homebrew_prefix();
    let brew_ruby = format!("{}/opt/ruby@{}/bin/ruby", brew_prefix, version);
    let brew_bundle = format!("{}/opt/ruby@{}/bin/bundle", brew_prefix, version);

    if std::path::Path::new(&brew_ruby).exists() {
        return Ok((PathBuf::from(brew_ruby), PathBuf::from(brew_bundle)));
    }

    let brew_ruby_generic = format!("{}/opt/ruby/bin/ruby", brew_prefix);
    let brew_bundle_generic = format!("{}/opt/ruby/bin/bundle", brew_prefix);

    if std::path::Path::new(&brew_ruby_generic).exists() {
        return Ok((
            PathBuf::from(brew_ruby_generic),
            PathBuf::from(brew_bundle_generic),
        ));
    }

    if let Some(rvm_ruby) = find_rvm_ruby_path(version) {
        let rvm_bundle = find_rvm_bundle_path(&rvm_ruby);
        return Ok((rvm_ruby, rvm_bundle));
    }

    Ok((local_ruby, local_bundle))
}

pub fn install_bundle_gems(ruby_path: &Path, bundle_path: &Path, app_path: &Path) -> Result<()> {
    let status = Command::new("/bin/bash")
        .arg("-c")
        .arg(format!(
            "export GEM_HOME={} && export PATH=\"{}:$PATH\" && cd '{}' && {} install",
            gem_home_for_version("3.4").display(),
            gem_home_for_version("3.4").join("bin").display(),
            app_path.display(),
            bundle_path.display()
        ))
        .status()?;

    if !status.success() {
        anyhow::bail!("Failed to install bundle gems");
    }

    Ok(())
}

fn expand_home(path: &str) -> PathBuf {
    if path.starts_with("~") {
        if let Some(home) = dirs::home_dir() {
            return PathBuf::from(path.replacen("~", home.to_str().unwrap(), 1));
        }
    }
    PathBuf::from(path)
}
