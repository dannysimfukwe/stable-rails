# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Workdir do
  let(:app) { { name: 'myapp', path: '/path/to/myapp' } }

  before do
    ENV['STABLE_TEST_MODE'] = 'true'
  end

  describe '#call' do
    context 'when app is not found' do
      before do
        allow(Stable::Services::AppRegistry).to receive(:find).and_return(nil)
      end

      it 'aborts with error message' do
        expect { described_class.new('myapp', 'vscode').call }.to raise_error(SystemExit, "App 'myapp' not found")
      end
    end

    context 'when app path does not exist' do
      before do
        allow(Stable::Services::AppRegistry).to receive(:find).and_return(app)
        allow(Dir).to receive(:exist?).and_return(false)
      end

      it 'aborts with error message' do
        expect { described_class.new('myapp', 'vscode').call }.to raise_error(SystemExit, 'App path does not exist: /path/to/myapp')
      end
    end

    context 'when editor command is not found' do
      before do
        allow(Stable::Services::AppRegistry).to receive(:find).and_return(app)
        allow(Dir).to receive(:exist?).and_return(true)
      end

      it 'aborts with error message' do
        allow_any_instance_of(described_class).to receive(:system).with('which unknown_editor > /dev/null 2>&1').and_return(false)
        expect { described_class.new('myapp', 'unknown_editor').call }.to raise_error(SystemExit, 'Editor command not found: unknown_editor')
      end
    end

    context 'when successful' do
      before do
        allow(Stable::Services::AppRegistry).to receive(:find).and_return(app)
        allow(Dir).to receive(:exist?).and_return(true)
      end

      it 'opens the app in the editor' do
        instance = described_class.new('myapp', 'vscode')
        allow(instance).to receive(:system).with('which code > /dev/null 2>&1').and_return(true)
        allow(instance).to receive(:system).with('code /path/to/myapp').and_return(true)
        expect { instance.call }.to output("🚀 Opening myapp in vscode...\n").to_stdout
      end

      it 'supports custom editors' do
        instance = described_class.new('myapp', 'custom')
        allow(instance).to receive(:system).with('which custom > /dev/null 2>&1').and_return(true)
        allow(instance).to receive(:system).with('custom /path/to/myapp').and_return(true)
        expect { instance.call }.to output("🚀 Opening myapp in custom...\n").to_stdout
      end
    end
  end
end
