require 'spec_helper'

RSpec.describe Stable::Commands::Remove do
  let(:app) { { name: 'remove_me', domain: 'remove_me.test', path: '/tmp/remove_me' } }

  it 'aborts when app not found' do
    allow(Stable::Services::AppRegistry).to receive(:find).and_return(nil)
    expect { described_class.new('nope').call }.to raise_error(SystemExit)
  end

  it 'removes an app when found' do
    allow(Stable::Services::AppRegistry).to receive(:find).with('remove_me').and_return(app)
    expect(Stable::Services::ProcessManager).to receive(:stop).with(app)
    expect(Stable::Services::HostsManager).to receive(:remove).with(app[:domain])
    expect(Stable::Services::CaddyManager).to receive(:remove).with(app[:domain])
    expect(Stable::Services::AppRegistry).to receive(:remove).with('remove_me')
    expect(Stable::Services::CaddyManager).to receive(:reload)

    expect { described_class.new('remove_me').call }.to output(/Removed remove_me/).to_stdout
  end
end
