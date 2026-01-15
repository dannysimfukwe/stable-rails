# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::AppStarterAll do
  let(:apps) do
    [
      {
        name: 'app1',
        pid: nil,
        started_at: nil,
        domain: 'app1.test',
        port: 3000,
        path: '/tmp/app1'
      },
      {
        name: 'app2',
        pid: 5678,
        started_at: Time.now.to_i,
        domain: 'app2.test',
        port: 3001,
        path: '/tmp/app2'
      },
      {
        name: 'app3',
        pid: nil,
        started_at: nil,
        domain: 'app3.test',
        port: 3002,
        path: '/tmp/app3'
      }
    ]
  end

  before do
    allow(Stable::Services::AppRegistry).to receive(:all).and_return(apps)
  end

  it 'starts all non-running apps' do
    # Mock app running status checks for all apps
    expect(Stable::Services::ProcessManager).to receive(:pid_alive?).with(5678).and_return(true)
    expect(Stable::Utils::Platform).to receive(:port_in_use?).with(3000).and_return(false)
    expect(Stable::Utils::Platform).to receive(:port_in_use?).with(3002).and_return(false)

    # Mock AppStarter calls for non-running apps
    expect(Stable::Services::AppStarter).to receive(:new).with('app1').and_return(double(call: true))
    expect(Stable::Services::AppStarter).to receive(:new).with('app3').and_return(double(call: true))
    expect(Stable::Services::AppStarter).not_to receive(:new).with('app2')

    described_class.new.call
  end

  it 'handles all apps already running' do
    # Mock all apps as running
    expect(Stable::Services::ProcessManager).to receive(:pid_alive?).with(5678).and_return(true)
    expect(Stable::Utils::Platform).to receive(:port_in_use?).with(3000).and_return(true)
    expect(Stable::Utils::Platform).to receive(:port_in_use?).with(3002).and_return(true)

    expect(Stable::Services::AppStarter).not_to receive(:new)

    described_class.new.call
  end

  it 'handles no apps registered' do
    allow(Stable::Services::AppRegistry).to receive(:all).and_return([])

    expect(Stable::Services::AppStarter).not_to receive(:new)

    described_class.new.call
  end
end
