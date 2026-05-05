use crate::stable::config::{AppConfig, next_available_port, save_app_config, update_caddyfile};
use crate::stable::utils::{
    apps_folder, ensure_hosts_entry, run_shell_output, shell_escape, slugify_name,
};
use crate::stable::ruby_manager;
use anyhow::Result;
use std::fs;
use std::path::Path;

#[derive(Debug, serde::Deserialize, Clone)]
pub struct RailsAppOptions {
    pub ruby_version: Option<String>,
    pub api_only: bool,
    pub database: String,
    pub db_user: Option<String>,
    pub db_password: Option<String>,
    pub install_devise: bool,
    pub install_rspec: bool,
    pub install_factory_bot: bool,
    pub install_sidekiq: bool,
    pub install_dotenv: bool,
}

pub fn run_with_progress<F, G>(app_name: &str, options: Option<RailsAppOptions>, progress: F, log: G) -> Result<()>
where
    F: Fn(&str),
    G: Fn(&str),
{
    let apps_root = apps_folder();
    fs::create_dir_all(&apps_root)?;

    let slug_name = slugify_name(app_name);
    if slug_name != app_name {
        log(&format!(
            "Using '{}' as the app folder and domain.",
            slug_name
        ));
    }

    let app_path = apps_root.join(&slug_name);

    if app_path.exists() {
        anyhow::bail!("App '{}' already exists", slug_name);
    }

    let opts = options.unwrap_or(RailsAppOptions {
        ruby_version: None,
        api_only: false,
        database: "sqlite3".to_string(),
        db_user: None,
        db_password: None,
        install_devise: false,
        install_rspec: false,
        install_factory_bot: false,
        install_sidekiq: false,
        install_dotenv: false,
    });

    let port = next_available_port();
    log(&format!("Assigning port {} to this app", port));

    // Build rails new command with flags
    let escaped_name = shell_escape(&slug_name);
    let mut rails_cmd = format!("rails new '{}' --skip-bundle", escaped_name);

    if opts.api_only {
        rails_cmd.push_str(" --api");
        log("Creating API-only Rails app");
    }

    if opts.database != "sqlite3" {
        rails_cmd.push_str(&format!(" --database={}", opts.database));
        log(&format!("Using {} database", opts.database));
    }

    progress("Creating Rails app...");
    let rails_output = run_shell_output(&apps_root, &rails_cmd)?;
    log_output(&log, &rails_output);
    if !rails_output.status.success() {
        anyhow::bail!("rails new failed for '{}'", app_name);
    }

    // Set Ruby version if specified
    if let Some(ref ruby_ver) = opts.ruby_version {
        let ruby_version_file = app_path.join(".ruby-version");
        fs::write(&ruby_version_file, ruby_ver)?;
        log(&format!("Set Ruby version to {}", ruby_ver));

        // Also update Gemfile ruby declaration if present
        let gemfile = app_path.join("Gemfile");
        if gemfile.exists() {
            if let Ok(content) = fs::read_to_string(&gemfile) {
                let updated = content.replace(
                    &format!("ruby \"{}\"", ruby_ver),
                    &format!("ruby \"{}\"", ruby_ver)
                );
                // If no ruby line exists, add it after source
                if !updated.contains("ruby \"") {
                    let with_ruby = updated.replacen(
                        "source ",
                        &format!("ruby \"{}\"\nsource ", ruby_ver),
                        1
                    );
                    let _ = fs::write(&gemfile, with_ruby);
                }
            }
        }
    }

    // Install additional gems
    if opts.install_devise || opts.install_rspec || opts.install_factory_bot || opts.install_sidekiq || opts.install_dotenv {
        progress("Adding gems to Gemfile...");
        let gemfile = app_path.join("Gemfile");
        let mut gemfile_content = fs::read_to_string(&gemfile)?;

        if opts.install_devise {
            gemfile_content.push_str("\ngem 'devise'\n");
            log("Added devise to Gemfile");
        }
        if opts.install_rspec {
            gemfile_content.push_str("\ngroup :development, :test do\n  gem 'rspec-rails'\nend\n");
            log("Added rspec-rails to Gemfile");
        }
        if opts.install_factory_bot {
            gemfile_content.push_str("\ngroup :development, :test do\n  gem 'factory_bot_rails'\nend\n");
            log("Added factory_bot_rails to Gemfile");
        }
        if opts.install_sidekiq {
            gemfile_content.push_str("\ngem 'sidekiq'\n");
            log("Added sidekiq to Gemfile");
        }
        if opts.install_dotenv {
            gemfile_content.push_str("\ngroup :development, :test do\n  gem 'dotenv-rails'\nend\n");
            log("Added dotenv-rails to Gemfile");
        }

        fs::write(&gemfile, gemfile_content)?;
    }

    // Run bundle install
    progress("Running bundle install...");
    let bundle_output = run_shell_output(&app_path, "bundle install")?;
    log_output(&log, &bundle_output);
    if !bundle_output.status.success() {
        log("Warning: bundle install had issues, continuing...");
    }

    // Update database.yml for MySQL/PostgreSQL with user-provided credentials
    if opts.database == "mysql" || opts.database == "postgresql" {
        let db_yml = app_path.join("config/database.yml");
        if db_yml.exists() {
            if let Ok(content) = fs::read_to_string(&db_yml) {
                let mut updated = content;
                let username = opts.db_user.as_deref().unwrap_or(
                    if opts.database == "postgresql" { "postgres" } else { "root" }
                );
                let password = opts.db_password.as_deref().unwrap_or("");

                if opts.database == "mysql" {
                    updated = updated.replace("username: root", &format!("username: {}", username));
                    // Replace empty password line or password with value
                    if password.is_empty() {
                        updated = updated.replace("password:", "password:");
                    } else {
                        updated = updated.replace("password:", &format!("password: {}", password));
                    }
                } else if opts.database == "postgresql" {
                    // PostgreSQL template often has commented-out username
                    updated = updated.replace("# username:", "username:");
                    updated = updated.replace("username:", &format!("username: {}", username));
                    if !password.is_empty() {
                        updated = updated.replace("# password:", "password:");
                        updated = updated.replace("password:", &format!("password: {}", password));
                    }
                }
                let _ = fs::write(&db_yml, updated);
                log(&format!("Updated database.yml with username: {}", username));
            }
        }
    }

    // Create the database so the app is ready to use immediately
    progress("Creating database...");
    let db_create_output = run_shell_output(&app_path, "bundle exec rails db:create")?;
    let db_stderr = String::from_utf8_lossy(&db_create_output.stderr).to_string();
    log_output(&log, &db_create_output);

    if db_create_output.status.success() {
        log("Database created successfully");
    } else if db_stderr.contains("Access denied") || db_stderr.contains("password") {
        log("⚠️  Database connection failed: incorrect username/password.");
        log("");
        log("For MySQL, fix this by updating config/database.yml:");
        log("  development:");
        log("    username: your_mysql_user");
        log("    password: your_mysql_password");
        log("");
        log("Or run: mysql -u root -p");
        log("  CREATE USER 'stable'@'localhost' IDENTIFIED BY 'stable';");
        log("  GRANT ALL PRIVILEGES ON *.* TO 'stable'@'localhost';");
        log("  FLUSH PRIVILEGES;");
        log("");
        log("Then update config/database.yml with those credentials.");
    } else if db_stderr.contains("Connection refused") || db_stderr.contains("can't connect") {
        log("⚠️  Database server is not running.");
        log("Start it with:");
        if opts.database == "mysql" {
            log("  brew services start mysql");
        } else if opts.database == "postgresql" {
            log("  brew services start postgresql");
        }
    } else {
        log("Warning: database creation had issues");
    }

    // Run generators for installed gems
    if opts.install_devise {
        progress("Installing Devise...");
        let devise_output = run_shell_output(&app_path, "bundle exec rails generate devise:install")?;
        log_output(&log, &devise_output);
        if devise_output.status.success() {
            log("Devise installed successfully");
        } else {
            log("Warning: Devise install had issues");
        }
    }

    if opts.install_rspec {
        progress("Installing RSpec...");
        let rspec_output = run_shell_output(&app_path, "bundle exec rails generate rspec:install")?;
        log_output(&log, &rspec_output);
        if rspec_output.status.success() {
            log("RSpec installed successfully");
        } else {
            log("Warning: RSpec install had issues");
        }
    }

    if opts.install_sidekiq {
        progress("Setting up Sidekiq...");
        // Create config/initializers/sidekiq.rb
        let initializer = app_path.join("config/initializers/sidekiq.rb");
        fs::create_dir_all(app_path.join("config/initializers"))?;
        fs::write(&initializer, "require 'sidekiq/web'\n")?;
        log("Sidekiq initializer created");
    }

    // Run db:migrate so the schema is up to date after generators
    progress("Running database migrations...");
    let db_migrate_output = run_shell_output(&app_path, "bundle exec rails db:migrate")?;
    let migrate_stderr = String::from_utf8_lossy(&db_migrate_output.stderr).to_string();
    log_output(&log, &db_migrate_output);

    if db_migrate_output.status.success() {
        log("Database migrated successfully");
    } else if migrate_stderr.contains("Access denied") || migrate_stderr.contains("password") {
        log("⚠️  Database migration failed: cannot connect to database.");
        log("The app was created but you'll need to fix database credentials.");
        log("Edit config/database.yml with your database username/password.");
    } else if migrate_stderr.contains("Unknown database") || migrate_stderr.contains("does not exist") {
        log("⚠️  Database doesn't exist yet. Run 'rails db:create' after fixing credentials.");
    } else {
        log("Warning: database migration had issues (this is normal for a fresh app)");
    }

    // Generate TLS certificates
    let cert_path = app_path.join("cert.pem");
    let key_path = app_path.join("key.pem");
    let domain = format!("{}.test", slug_name);
    let _ = ensure_hosts_entry(&domain)?;

    if !cert_path.exists() || !key_path.exists() {
        progress("Generating TLS certificates...");
        let mkcert_output = run_shell_output(&app_path, &format!("mkcert '{}.test'", escaped_name));

        if let Ok(output) = mkcert_output {
            log_output(&log, &output);
            if output.status.success() {
                let generated_cert = app_path.join(format!("{}.test.pem", slug_name));
                let generated_key = app_path.join(format!("{}.test-key.pem", slug_name));
                if let Err(err) = fs::rename(generated_cert, &cert_path) {
                    log(&format!("Warning: could not move cert file: {}", err));
                }
                if let Err(err) = fs::rename(generated_key, &key_path) {
                    log(&format!("Warning: could not move key file: {}", err));
                }
            } else {
                log("mkcert failed; continuing without custom certs.");
            }
        }
    }

    // Save app config
    let mut app_config = AppConfig::default();
    app_config.name = slug_name.clone();
    app_config.path = app_path.clone();
    app_config.port = port;
    app_config.domain = domain.clone();
    app_config.rails_env = "development".to_string();
    app_config.tls_enabled = true;
    app_config.caddy_enabled = true;
    save_app_config(&app_config)?;
    log(&format!("Saved config for {} on port {}", slug_name, port));

    progress("Updating Caddy configuration...");
    update_caddyfile()?;
    log("Caddy configuration updated.");

    progress("Stable app ready.");
    Ok(())
}

pub fn run(app_name: &str) -> Result<()> {
    run_with_progress(app_name, None, |_| {}, |_| {})
}

fn log_output<F>(log: &F, output: &std::process::Output)
where
    F: Fn(&str),
{
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if !line.trim().is_empty() {
            log(line);
        }
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    for line in stderr.lines() {
        if !line.trim().is_empty() {
            log(line);
        }
    }
}
