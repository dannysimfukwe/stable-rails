# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::Services::HostsManager do
  it 'adds and removes host entries' do
    tmp_hosts = File.join(Stable::Paths.root, 'hosts')
    FileUtils.mkdir_p(File.dirname(tmp_hosts))
    File.write(tmp_hosts, '')

    # Temporarily override the hosts_file method
    allow(described_class).to receive(:hosts_file).and_return(tmp_hosts)

    # Mock Process.uid to return 0 (root)
    allow(Process).to receive(:uid).and_return(0)

    described_class.add('example.test')
    expect(File.read(tmp_hosts)).to include('example.test')

    described_class.remove('example.test')
    expect(File.read(tmp_hosts)).not_to include('example.test')
  end
end
