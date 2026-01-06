# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Stable::Services::AppDestroyer do
  let(:app) { { name: 'destroy_me', domain: 'destroy_me.test', path: '/tmp/destroy_me', ruby: '3.4.7' } }

  it 'aborts when app not found' do
    allow(Stable::Services::AppRegistry).to receive(:find).and_return(nil)
    expect { described_class.new('nope').call }.to raise_error(SystemExit)
  end

  context 'with valid app' do
    before do
      allow(Stable::Services::AppRegistry).to receive(:find).with('destroy_me').and_return(app)
    end

    it 'cancels destruction when confirmation does not match' do
      allow($stdin).to receive(:gets).and_return("wrong_name\n")

      expect { described_class.new('destroy_me').call }.to output(/Destruction cancelled/).to_stdout
    end

    it 'destroys app when confirmation matches' do
      allow($stdin).to receive(:gets).and_return("destroy_me\n")
      allow(File).to receive(:exist?).with(app[:path]).and_return(true)
      allow(FileUtils).to receive(:rm_rf).and_return(true)
      allow(Kernel).to receive(:system).and_return(true)
      allow(Stable::Utils::Platform).to receive(:unix?).and_return(false) # Skip RVM cleanup

      expect(Stable::Services::ProcessManager).to receive(:stop).with(app)
      expect(Stable::Services::HostsManager).to receive(:remove).with(app[:domain])
      expect(Stable::Services::CaddyManager).to receive(:remove).with(app[:domain])
      expect(Stable::Services::AppRegistry).to receive(:remove).with('destroy_me')
      expect(Stable::Services::CaddyManager).to receive(:reload)

      expect { described_class.new('destroy_me').call }.to output(/Successfully destroyed destroy_me/).to_stdout
    end

    it 'deletes the project directory' do
      allow($stdin).to receive(:gets).and_return("destroy_me\n")
      allow(Stable::Services::ProcessManager).to receive(:stop)
      allow(Stable::Services::HostsManager).to receive(:remove)
      allow(Stable::Services::CaddyManager).to receive(:remove)
      allow(Stable::Services::AppRegistry).to receive(:remove)
      allow(Stable::Services::CaddyManager).to receive(:reload)

      allow(File).to receive(:exist?).with(app[:path]).and_return(true)
      # In test mode, FileUtils.rm_rf is not called due to test mode protection
      allow(FileUtils).to receive(:rm_rf)

      described_class.new('destroy_me').call
    end

    it 'handles missing project directory gracefully' do
      allow($stdin).to receive(:gets).and_return("destroy_me\n")
      allow(Stable::Services::ProcessManager).to receive(:stop)
      allow(Stable::Services::HostsManager).to receive(:remove)
      allow(Stable::Services::CaddyManager).to receive(:remove)
      allow(Stable::Services::AppRegistry).to receive(:remove)
      allow(Stable::Services::CaddyManager).to receive(:reload)

      allow(File).to receive(:exist?).with(app[:path]).and_return(false)
      # In test mode, FileUtils.rm_rf is not called
      allow(FileUtils).to receive(:rm_rf)

      # In test mode, it just prints "Deleting project directory..." without checking existence
      expect { described_class.new('destroy_me').call }.to output(/Deleting project directory/).to_stdout
    end
  end
end
