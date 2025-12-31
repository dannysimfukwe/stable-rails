# Stable CLI (macOS)

Stable is a CLI tool to manage local Rails applications with automatic Caddy setup on macOS, local trusted HTTPS certificates, and easy start/stop functionality.

## Features

- Add and remove Rails apps.
- Automatically generate and manage local HTTPS certificates using `mkcert`.
- Automatically update `/etc/hosts` for `.test` domains.
- Start Rails apps with integrated Caddy reverse proxy.
- Reload Caddy after adding/removing apps.
- List all registered apps.

## Installation

### From source

```bash
# Clone the repository
git clone git@github.com:dannysimfukwe/stable-rails.git
cd stable-rails

# Install dependencies
bundle install
```

### As a gem from Rubygems registry

```bash
gem install stable-cli-rails
```

### Or add it to your Gemfile
```bash
gem "stable-cli-rails" 
```

## Setup

Initialize Caddy home and required directories:

```bash
stable setup
```

This will create:  
- `~/StableCaddy/` for Caddy configuration.  
- `~/StableCaddy/certs` for generated certificates.  
- `~/StableCaddy/Caddyfile` for Caddy configuration.  

## CLI Commands

### List apps

```bash
stable list
```

Lists all registered apps and their domains.

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
stable caddy reload
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

### Create a new Rails app

```bash
stable new myapp [--ruby 3.4.4] [--rails 7.0.7.1] [--skip-ssl]
```

Creates a new Rails app, generates `.ruby-version`, installs Rails, adds the app to Stable, and optionally secures it with HTTPS.

## Paths

- Caddy home: `~/StableCaddy`  
- Caddyfile: `~/StableCaddy/Caddyfile`  
- Certificates: `~/StableCaddy/certs`  
- Registered apps: `~/StableCaddy/apps.yml`  

## Dependencies

- Homebrew  
- Caddy  
- mkcert  
- RVM (or rbenv fallback)

`ensure_dependencies!` will install missing dependencies automatically.

## Known Issues

- Sometimes you may see:  
```
TCPSocket#initialize: Connection refused - connect(2) for "127.0.0.1" port 300.. (Errno::ECONNREFUSED)
```
This usually disappears after a few seconds when Caddy reloads. If it persists, run:

```bash
stable secure myapp.test
```

- Some commands may need to be run consecutively for proper setup:  
```bash
stable setup
stable add myapp or stable new myapp
stable secure myapp.test
stable start myapp
```

- PATH warnings from RVM may appear on the first run. Make sure your shell is properly configured for RVM.

## Notes

- Make sure to run `stable setup` initially.  
- Requires `sudo` to modify `/etc/hosts`.  
- Rails apps are started on ports assigned by Stable (default 3000+).  
- Domains are automatically suffixed with `.test`.  

## License

MIT License
