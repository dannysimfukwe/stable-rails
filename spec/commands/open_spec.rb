# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Open do
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
    allow(Stable::Services::AppRegistry)
      .to receive(:find)
      .with(app_name)
      .and_return(app)
  end

  describe '#call' do
    context 'when app exists' do
      before do
        allow(command).to receive(:open_browser)
      end

      it 'opens the app using its domain' do
        expect(command)
          .to receive(:open_browser)
          .with('https://myapp.test')

        command.call
      end

      it 'prints a success message' do
        expect do
          command.call
        end.to output(%r{Opened https://myapp\.test}).to_stdout
      end
    end

    context 'when app does not exist' do
      before do
        allow(Stable::Services::AppRegistry)
          .to receive(:find)
          .with(app_name)
          .and_return(nil)
      end

      it 'aborts with a clear error' do
        expect do
          command.call
        end.to raise_error(SystemExit, /App 'myapp' not found/)
      end
    end
  end

  describe '#open_browser' do
    it 'uses macOS open command' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')

      expect(command)
        .to receive(:system)
        .with('open https://myapp.test')
        .and_return(true)

      command.send(:open_browser, 'https://myapp.test')
    end

    it 'uses Linux xdg-open command' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux')

      expect(command)
        .to receive(:system)
        .with('xdg-open https://myapp.test')
        .and_return(true)

      command.send(:open_browser, 'https://myapp.test')
    end
  end
end
