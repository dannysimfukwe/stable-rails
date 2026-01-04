# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::UpgradeRuby do
  describe '#call' do
    let(:app) { { name: 'test-app', domain: 'test-app.test', path: '/tmp/test-app', ruby: '3.4.4' } }
    let(:command) { described_class.new('test-app', '3.4.7') }

    before do
      # Skip bootstrap and dependency checks in tests
      allow(Stable::Bootstrap).to receive(:run!)
      allow(Stable::Services::SetupRunner).to receive(:ensure_dependencies!)

      allow(Stable::Services::AppRegistry).to receive(:find).and_return(app)
      allow(Stable::Services::Ruby).to receive(:rvm_available?).and_return(true)
      allow(Stable::Services::Ruby).to receive(:rbenv_available?).and_return(false)
      allow(Stable::Services::Ruby).to receive(:rvm_script).and_return('/mock/rvm/scripts/rvm')
      allow(Stable::Services::AppRegistry).to receive(:update)
      allow(File).to receive(:write)
      allow(File).to receive(:delete)
    end

    it 'upgrades Ruby version with clean gemset recreation' do
      # Mock ALL system interactions to prevent real execution
      allow(Stable::System::Shell).to receive(:run).and_return(true)
      allow(Kernel).to receive(:system).and_return(true)
      allow(File).to receive(:exist?).and_return(false)

      expect { command.call }.to output(/Upgrading test-app from Ruby 3.4.4 to 3.4.7/).to_stdout
    end

    it 'allows downgrades to lower versions' do
      command_downgrade = described_class.new('test-app', '3.4.0')

      # Mock ALL system interactions to prevent real execution
      allow(Stable::System::Shell).to receive(:run).and_return(true)
      allow(Kernel).to receive(:system).and_return(true)
      allow(File).to receive(:exist?).and_return(false)

      expect { command_downgrade.call }.to output(/Downgrading test-app from Ruby 3.4.4 to 3.4.0/).to_stdout
    end

    it 'handles patch version switches' do
      command_patch = described_class.new('test-app', '3.4.5')

      # Mock ALL system interactions to prevent real execution
      allow(Stable::System::Shell).to receive(:run).and_return(true)
      allow(Kernel).to receive(:system).and_return(true)
      allow(File).to receive(:exist?).and_return(false)

      expect { command_patch.call }.to output(/Upgrading test-app from Ruby 3.4.4 to 3.4.5/).to_stdout
    end
  end
end
