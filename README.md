# Stable CLI

Stable is a CLI tool to manage local Rails applications with automatic Caddy setup, local trusted HTTPS certificates, and easy start/stop functionality.

## Features

- Add and remove Rails apps.
- Automatically generate and manage local HTTPS certificates using `mkcert`.
- Automatically update `/etc/hosts` for `.test` domains.
- Start Rails apps with integrated Caddy reverse proxy.
- Reload Caddy after adding/removing apps.
- List all registered apps.
- Create a new Rails app with automatic setup.
- Upgrade Ruby versions for existing apps.
- Run a health check with `stable doctor`.

## Installation

Make sure you have:
- [Homebrew](https://brew.sh)
- [Ruby](https://www.ruby-lang.org)
- [Rails](https://rubyonrails.org)

Then install Stable:

### As a gem

```bash
gem install stable
```

### From source

```bash
# Clone the repository
git clone git@github.com:dannysimfukwe/stable-rails.git
cd stable-rails

# Install dependencies
bundle install
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
rvmsudo stable start app_name
```

Starts the Rails server on the app's assigned port and ensures Caddy is running with the proper reverse proxy. Rails logs can be viewed in your terminal.

### Stop an app

```bash
stable stop app_name
```

Stops the Rails server.

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

### Create a new Rails app

```bash
stable new myapp [--ruby 3.4.4] [--rails 7.0.7] [--skip-ssl]
```

Creates a new Rails app, generates `.ruby-version`, sets up HTTPS, adds to registry, and starts the app.

### Upgrade Ruby for an app

```bash
stable upgrade-ruby app_name 3.4.4
```

Upgrades the Ruby version for an existing app and reconfigures its environment.

### Health check

```bash
stable doctor
```

Checks dependencies, Caddy, Ruby, Rails, and app connectivity.

## Paths

- Caddy home: `~/StableCaddy`
- Caddyfile: `~/StableCaddy/Caddyfile`
- Certificates: `~/StableCaddy/certs`
- Registered apps: `~/StableCaddy/apps.yml`

## Dependencies

- Homebrew
- Caddy
- mkcert

`ensure_dependencies!` will install missing dependencies automatically.

## Notes

- Make sure to run `stable setup` initially.
- Requires `sudo` to modify `/etc/hosts`.
- Caddy runs in the background by default.
- Rails apps are started on dynamic ports by default.
- Domains are automatically suffixed with `.test`.
- Supports RVM and falls back to rbenv if RVM is unavailable.

## License

MIT License
