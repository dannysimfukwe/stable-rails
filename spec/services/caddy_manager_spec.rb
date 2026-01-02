# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::Services::CaddyManager do
  it 'adds app block to caddyfile and creates certs when present' do
    caddyfile = File.join(Stable::Paths.root, 'Caddyfile')
    certs_dir = File.join(Stable::Paths.root, 'certs')

    stub_const('Stable::Services::CaddyManager::CADDYFILE', caddyfile)

    # create an app entry and certs
    app = { name: 'cadtest', path: '/tmp/cadtest', domain: 'cadtest.test', port: 3600 }
    Stable::Registry.save([app])

    FileUtils.mkdir_p(certs_dir)
    cert = File.join(certs_dir, "#{app[:domain]}.pem")
    key = File.join(certs_dir, "#{app[:domain]}-key.pem")
    File.write(cert, 'cert')
    File.write(key, 'key')

    described_class.add_app('cadtest')

    expect(File.read(caddyfile)).to include(app[:domain])
  end
end
