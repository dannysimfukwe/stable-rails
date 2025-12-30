# Stable CLI

Stable is a CLI tool to manage local Rails applications with automatic Caddy setup, local trusted HTTPS certificates, and easy start/stop functionality.

## Features

- Add and remove Rails apps.
- Automatically generate and manage local HTTPS certificates using `mkcert`.
- Automatically update `/etc/hosts` for `.test` domains.
- Start Rails apps with integrated Caddy reverse proxy.
- Reload Caddy after adding/removing apps.
- List all registered apps.

## Installation

Make sure you have:
- [Homebrew](https://brew.sh)
- [Ruby](https://www.ruby-lang.org)
- [Rails](https://rubyonrails.org)

Then install Stable:

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

Starts the Rails server on port 3000 and ensures Caddy is running with the proper reverse proxy. Rails logs can be viewed in your terminal.

### Stop an app

```bash
stable stop app_name
```

Stops the Rails server running on port 3000.

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
- Caddy runs on background by default but logs can be checked in your terminal if `spawn` is configured with stdout/stderr attached.
- Rails apps are started on port 3000 by default.
- Domains are automatically suffixed with `.test`.

## License

MIT License

