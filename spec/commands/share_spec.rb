# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Share do
  let(:app) { { name: 'myapp', port: 3001, pid: 12_345, domain: 'myapp.test', skip_ssl: false } }

  before do
    ENV['STABLE_TEST_MODE'] = 'true'
    allow(Stable::Services::AppRegistry).to receive(:find).and_return(app)
    allow(Stable::Services::Rails::HostAuthorization).to receive(:allow_ngrok!)
    allow(Stable::Services::ProcessManager).to receive(:stop)
    allow(Stable::Services::ProcessManager).to receive(:start)
    allow_any_instance_of(Stable::Services::Tunneling::Manager).to receive(:expose_domain).and_return('https://3001-stable-share.test')
    allow(Process).to receive(:kill).and_return(true)
  end

  it 'prints the shared URL' do
    expect do
      described_class.new('myapp').call
    end.to output("🌐 Shared myapp at:\n   https://3001-stable-share.test\n").to_stdout
  end

  context 'with qrcode option' do
    before do
      allow(Stable::Services::Cli::QrCode).to receive(:print)
    end

    it 'prints the QR code' do
      expect(Stable::Services::Cli::QrCode).to receive(:print).with('https://3001-stable-share.test')
      expect do
        described_class.new('myapp', qrcode: true).call
      end.to output("🌐 Shared myapp at:\n   https://3001-stable-share.test\n").to_stdout
    end
  end

  context 'when app is not found' do
    before do
      allow(Stable::Services::AppRegistry).to receive(:find).and_return(nil)
    end

    it 'aborts with error message' do
      expect { described_class.new('unknown').call }.to raise_error(SystemExit, "App 'unknown' not found")
    end
  end

  context 'when app is not running' do
    let(:app_no_pid) { { name: 'myapp', port: 3001, domain: 'myapp.test', skip_ssl: false } }

    before do
      allow(Stable::Services::AppRegistry).to receive(:find).and_return(app_no_pid)
    end

    it 'aborts with error message' do
      expect { described_class.new('myapp').call }.to raise_error(SystemExit, "App 'myapp' is not running")
    end
  end
end
