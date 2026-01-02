# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::Services::SetupRunner do
  it 'creates required directories and files and ensures deps' do
    tmp_home = Stable::Paths.root
    stub_const('Stable::Services::SetupRunner::STABLE_HOME', tmp_home)

    # stub external installs/checks
    allow_any_instance_of(Object).to receive(:system).and_return(true)

    described_class.new.call

    expect(Dir.exist?(File.join(tmp_home, 'certs'))).to be true
    expect(File.exist?(File.join(tmp_home, 'apps.yml'))).to be true
    expect(File.exist?(File.join(tmp_home, 'Caddyfile'))).to be true
  end
end
