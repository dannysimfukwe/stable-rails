# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::AppOpener do
  let(:app_name) { 'myapp' }
  let(:command) { described_class.new(app_name) }

  let(:app) do
    {
      name: app_name,
      domain: 'myapp.test',
      port: 3001,
      pid: 12_345,
      started_at: Time.now.to_i
    }
  end

  before do
    # Stub AppRegistry to find the app
    allow(Stable::Services::AppRegistry).to receive(:find).with(app_name).and_return(app)

    # Stub system and abort to prevent real side effects
    allow(command).to receive(:system)
    allow(command).to receive(:abort)
  end

  describe '#call' do
    context 'when app exists' do
      it 'opens the app using its domain' do
        expect(command).to receive(:open_browser).with("https://#{app[:domain]}")
        expect { command.call }.to output(%r{Opened https://#{app[:domain]}}).to_stdout
      end
    end

    context 'when app does not exist' do
      let(:missing_app_name) { 'missing_app' }
      let(:missing_command) { described_class.new(missing_app_name) }

      before do
        allow(Stable::Services::AppRegistry).to receive(:find).with(missing_app_name).and_return(nil)
        allow(missing_command).to receive(:abort)
      end
      it 'aborts when app is not running' do
        allow(Stable::Services::AppRegistry).to receive(:find).and_return(
          { pid: nil, domain: 'myapp.test' }
        )
        command = described_class.new('myapp')
        expect do
          command.call
        end.to raise_error(SystemExit, /not running/)
      end
    end
  end

  describe '#open_browser' do
    it 'uses macOS open command' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')
      expect(command).to receive(:system).with("open https://#{app[:domain]}")
      command.send(:open_browser, "https://#{app[:domain]}")
    end

    it 'uses Linux xdg-open command' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux')
      expect(command).to receive(:system).with("xdg-open https://#{app[:domain]}")
      command.send(:open_browser, "https://#{app[:domain]}")
    end
  end
end
