# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::AppRestarter do
  let(:name) { 'myapp' }
  let(:app) do
    {
      name: name,
      pid: 1234,
      domain: "#{name}.test",
      port: 3000,
      path: "/tmp/#{name}"
    }
  end

  before do
    allow(Stable::Registry).to receive(:apps).and_return([app])
  end

  it 'stops a running app then starts it' do
    expect(Process).to receive(:kill).with('TERM', 1234)
    expect(Stable::Services::AppStarter).to receive(:new).with(name).and_return(double(call: true))
    expect(Stable::Services::AppRegistry).to receive(:update).with(name, started_at: nil, pid: nil)

    described_class.new(name).call
  end

  it 'starts app when not running' do
    app_no_pid = app.merge(pid: nil)
    allow(Stable::Registry).to receive(:apps).and_return([app_no_pid])

    expect(Process).not_to receive(:kill)
    expect(Stable::Services::AppStarter).to receive(:new).with(name).and_return(double(call: true))

    described_class.new(name).call
  end
end
