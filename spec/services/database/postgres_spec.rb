# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::Database::Postgres do
  let(:app_path) { File.join(Stable::Paths.root, 'pgapp') }

  before { FileUtils.mkdir_p(app_path) }

  it 'runs createdb and prepares the database' do
    db = described_class.new(app_name: 'pgdb', app_path: app_path)

    allow(Stable::System::Shell).to receive(:run).and_return(true)

    expect { db.setup }.not_to raise_error
    expect(Stable::System::Shell).to have_received(:run).with('createdb pgdb')
    expect(Stable::System::Shell).to have_received(:run).with(/bundle exec rails db:prepare/)
  end

  it 'raises when createdb fails' do
    db = described_class.new(app_name: 'pgfail', app_path: app_path)
    allow(Stable::System::Shell).to receive(:run).with('createdb pgfail').and_raise('Command failed')

    expect { db.setup }.to raise_error(RuntimeError)
  end
end
