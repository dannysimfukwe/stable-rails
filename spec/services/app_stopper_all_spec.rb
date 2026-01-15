# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::AppStopperAll do
  let(:apps) do
    [
      {
        name: 'app1',
        pid: 1234,
        domain: 'app1.test',
        port: 3000,
        path: '/tmp/app1'
      },
      {
        name: 'app2',
        pid: 5678,
        domain: 'app2.test',
        port: 3001,
        path: '/tmp/app2'
      },
      {
        name: 'app3',
        pid: nil,
        domain: 'app3.test',
        port: 3002,
        path: '/tmp/app3'
      }
    ]
  end

  before do
    allow(Stable::Services::AppRegistry).to receive(:all).and_return(apps)
  end

  it 'stops all running apps' do
    expect(Stable::Utils::Platform).to receive(:find_pids_by_port).with(3000).and_return([1234])
    expect(Stable::Utils::Platform).to receive(:find_pids_by_port).with(3001).and_return([5678])
    expect(Stable::Utils::Platform).to receive(:find_pids_by_port).with(3002).and_return([])

    expect(Stable::Services::ProcessManager).to receive(:stop).with(apps[0])
    expect(Stable::Services::ProcessManager).to receive(:stop).with(apps[1])
    expect(Stable::Services::ProcessManager).not_to receive(:stop).with(apps[2])

    expect(Stable::Services::AppRegistry).to receive(:mark_stopped).with('app1')
    expect(Stable::Services::AppRegistry).to receive(:mark_stopped).with('app2')
    expect(Stable::Services::AppRegistry).not_to receive(:mark_stopped).with('app3')

    described_class.new.call
  end

  it 'handles no running apps' do
    expect(Stable::Utils::Platform).to receive(:find_pids_by_port).with(3000).and_return([])
    expect(Stable::Utils::Platform).to receive(:find_pids_by_port).with(3001).and_return([])
    expect(Stable::Utils::Platform).to receive(:find_pids_by_port).with(3002).and_return([])

    expect(Stable::Services::ProcessManager).not_to receive(:stop)
    expect(Stable::Services::AppRegistry).not_to receive(:mark_stopped)

    described_class.new.call
  end
end
