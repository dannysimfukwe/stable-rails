# Stable CLI

Stable is a cross-platform CLI tool to manage local Rails applications with automatic Caddy setup, local trusted HTTPS certificates, and easy start/stop functionality. Supports macOS, Linux, and Windows.

## Features

- Add and remove Rails apps.
- Automatically generate and manage local HTTPS certificates using `mkcert`.
- Automatically assign `.test` domains.
- Start Rails apps with integrated Caddy reverse proxy.
- Reload Caddy after adding/removing apps.
- List all registered apps.

## Installation

```bash
gem install stable-cli-rails
```

### Or add it to your Gemfile
```bash
gem "stable-cli-rails"
```

## Platform-Specific Setup

### macOS
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Stable CLI
gem install stable-cli-rails

# Run setup
stable setup
```

### Linux (Ubuntu/Debian)
```bash
# Update package lists and install build tools
sudo apt update
sudo apt install -y build-essential curl

# Install Ruby (if not already installed)
sudo apt install -y ruby ruby-dev

# Install Stable CLI
gem install stable-cli-rails

# Run setup
stable setup
```

### Linux (CentOS/RHEL)
```bash
# Install build tools
sudo yum install -y gcc gcc-c++ make curl

# Install Ruby (if not already installed)
sudo yum install -y ruby ruby-devel

# Install Stable CLI
gem install stable-cli-rails

# Run setup
stable setup
```

### Windows
```bash
# Install Ruby from https://rubyinstaller.org/
# Install Git for Windows (includes Git Bash)
# Install dependencies manually:
# - Caddy: https://caddyserver.com/docs/install
# - mkcert: https://github.com/FiloSottile/mkcert/releases
# - PostgreSQL: https://www.postgresql.org/download/windows/
# - MySQL: https://dev.mysql.com/downloads/mysql/

# Install Stable CLI
gem install stable-cli-rails

# Run setup (may require manual dependency installation)
stable setup
```

## Setup

Initialize Caddy home and required directories:

```bash
stable setup
```

This will create:
- `~/StableCaddy/` for Caddy configuration.
- `~/StableCaddy/certs` for generated certificates.
- `~/StableCaddy/projects` for Rails applications.
- `~/StableCaddy/Caddyfile` for Caddy configuration.  

## CLI Commands

### List apps

```bash
# List all registered apps
stable list
```

Lists all registered apps and their domains.

### Create a new Rails app

```bash
# Create a new Rails app with options
stable new myapp [--ruby 3.4.4] [--rails 8.1.1] [--skip-ssl] [--db --mysql] [--db --postgres]

# Create a new Rails app with default sqlite
stable new myapp
```

Creates a new Rails app, generates `.ruby-version`, installs Rails, adds the app to Stable, and optionally secures it with HTTPS.

#### Database Support

You can create Rails apps with integrated database support using the `--mysql` or `--postgres` flags. Stable will handle gem installation, database creation, and configuration automatically.

```bash
# Create a new Rails app with PostgreSQL
stable new myapp --db --postgres

# Create a new Rails app with MySQL
stable new myapp --db --mysql
```

- The CLI will prompt for the database root username and password during setup.  
- The corresponding gem (`pg` for PostgreSQL or `mysql2` for MySQL) will be added to the Gemfile automatically.  
- `database.yml` will be configured for `development`, `test`, and `production` environments.  
- The database will be created and prepared (`rails db:prepare`) automatically.  

### Add a Rails app

```bash
stable add /path/to/rails_app
```

This will:  
- Register the app.  
- Add a `/etc/hosts` entry.  
- Generate local trusted HTTPS certificates.  
- Add a Caddy reverse proxy block.  
- Reload Caddy.

### Remove a Rails app

```bash
stable remove app_name
```

This will:  
- Remove the app from registry.  
- Remove `/etc/hosts` entry.  
- Remove the Caddy reverse proxy block.  
- Reload Caddy.

### Start an app

```bash
stable start app_name
```

Starts the Rails server on the assigned port and ensures Caddy is running with the proper reverse proxy. Rails logs can be viewed in your terminal.

### Stop an app

```bash
stable stop app_name
```

Stops the Rails server running on the assigned port.

### Secure an app manually

```bash
stable secure app_name.test
```

Generates or updates trusted local HTTPS certificates and reloads Caddy.

### Reload Caddy

```bash
stable caddy_reload
```

Reloads Caddy configuration after changes.

### Health check

```bash
stable doctor
```

Checks the environment, RVM/Ruby, Caddy, mkcert, and app readiness.

### Upgrade Ruby for an app

```bash
stable upgrade-ruby myapp 3.4.4
```

Upgrades the Ruby version for a specific app, updating `.ruby-version` and ensuring gemset compatibility.

## Testing

Stable uses RSpec for testing. To run the test suite:

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/commands/new_spec.rb

# Run with Rake (same as bundle exec rspec)
rake spec
```

The test suite includes:
- Unit tests for all services and commands
- Integration tests for CLI functionality
- Cross-platform compatibility tests
- Database integration tests

### Test Structure

```
spec/
├── cli/                    # CLI integration tests
├── commands/              # Command-specific tests
├── services/              # Service layer tests
│   └── database/          # Database-specific tests
├── spec_helper.rb         # Test configuration
└── spec.opts             # RSpec options
```

## Paths

- Caddy home: `~/StableCaddy`
- Caddyfile: `~/StableCaddy/Caddyfile`
- Certificates: `~/StableCaddy/certs`
- Projects directory: `~/StableCaddy/projects`
- App configurations: `~/StableCaddy/projects/{app_name}/{app_name}.yml`  

## Dependencies

### Package Manager (one of):
- **macOS**: Homebrew
- **Linux**: APT (Ubuntu/Debian), YUM/DNF (CentOS/RHEL), or Pacman (Arch)
- **Windows**: Manual installation required

### Core Dependencies:
- **Caddy**: Web server and reverse proxy
- **mkcert**: Local HTTPS certificate generation
- **Ruby version manager**: RVM, rbenv, or chruby
- **PostgreSQL**: Database server (optional)
- **MySQL**: Database server (optional)

`stable setup` will attempt to install missing dependencies automatically on macOS and Linux. On Windows, manual installation is required.

## Notes

- Make sure to run `stable setup` initially.
- **macOS/Linux**: Requires `sudo` to modify `/etc/hosts`.
- **Windows**: Requires administrator privileges to modify `C:\Windows\System32\drivers\etc\hosts`.
- Rails apps are started on ports assigned by Stable (default 3000+).
- Domains are automatically suffixed with `.test`.
- **Windows**: Some features may have limited support. Manual installation of dependencies is required.

## How to Contribute

We welcome contributions to Stable! Here's how to get started:

### Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/stable-cli.git
   cd stable-cli
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Run tests**
   ```bash
   bundle exec rspec
   ```

4. **Install locally for testing**
   ```bash
   gem build stable-cli-rails.gemspec
   gem install stable-cli-rails-*.gem
   ```

### Development Workflow

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** and ensure tests pass
   ```bash
   bundle exec rspec
   ```

3. **Follow the coding standards**
   - Use `bundle exec rubocop` to check code style
   - Write tests for new features
   - Update documentation as needed

4. **Submit a pull request**
   - Ensure all tests pass
   - Update CHANGELOG.md if applicable
   - Provide a clear description of changes

### Cross-Platform Testing

Since Stable supports multiple platforms, please test on:
- macOS (primary development platform)
- Linux (Ubuntu/Debian recommended)
- Windows (if possible, or document limitations)

### Reporting Issues

When reporting bugs, please include:
- Your operating system and version
- Ruby version (`ruby -v`)
- Steps to reproduce the issue
- Expected vs actual behavior

## License

MIT License

