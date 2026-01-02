# frozen_string_literal: true

module Stable
  module Config
    APP_ROOT = File.expand_path('~/StableCaddy')
    CADDYFILE = File.join(APP_ROOT, 'Caddyfile')
    REGISTRY = File.join(APP_ROOT, 'apps.yml')
  end
end
