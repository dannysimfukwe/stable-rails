# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::Services::ProcessManager do
  before do
    # create an app and persist
    @app = { name: 'pmtest', path: File.join(Stable::Paths.root, 'pmtest'), domain: 'pmtest.test', port: 3500 }
    FileUtils.mkdir_p(@app[:path])
    Stable::Registry.save_app_config('pmtest', @app)
  end

  it 'starts a process and updates registry' do
    allow_any_instance_of(Object).to receive(:spawn).and_return(9999)
    allow(Process).to receive(:detach)

    pid = described_class.start('pmtest')
    expect(pid).to eq(9999)

    stored = Stable::Services::AppRegistry.find('pmtest')
    expect(stored[:pid]).to eq(9999)
    expect(stored[:started_at]).to be_a(Integer)
  end
end
