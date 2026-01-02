# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::Database::MySQL do
  let(:app_path) { File.join(Stable::Paths.root, 'mysqlapp') }

  before { FileUtils.mkdir_p(File.join(app_path, 'config')) }

  it 'creates database, writes database.yml and prepares' do
    db = described_class.new(app_name: 'mysqldb', app_path: app_path)

    allow(Stable::Utils::Prompts).to receive(:mysql_root_credentials).and_return(user: 'root', password: '')
    allow(Stable::System::Shell).to receive(:run).and_return(true)

    expect { db.setup }.not_to raise_error

    cfg = YAML.load_file(File.join(app_path, 'config', 'database.yml'))
    expect(cfg['default']['adapter']).to eq('mysql2')
    expect(cfg['default']['database']).to eq('mysqldb')
  end

  it 'propagates when create_database fails' do
    db = described_class.new(app_name: 'mysqlfail', app_path: app_path)
    allow(Stable::Utils::Prompts).to receive(:mysql_root_credentials).and_return(user: 'root', password: '')
    allow(Stable::System::Shell).to receive(:run).and_raise('mysql failed')

    expect { db.setup }.to raise_error(RuntimeError)
  end
end
