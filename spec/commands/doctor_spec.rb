# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Doctor do
  it 'prints summary of checks' do
    checks = [
      { name: 'c1', ok: true, message: '' },
      { name: 'c2', ok: false, message: 'broken' }
    ]
    checker = double(run: checks)
    expect(Stable::Services::DependencyChecker).to receive(:new).and_return(checker)

    out = StringIO.new
    $stdout = out
    begin
      described_class.new.call
    ensure
      $stdout = STDOUT
    end

    output = out.string
    expect(output).to include('Running Stable health checks')
    expect(output).to include('c1')
    expect(output).to include('c2')
    expect(output).to include('issue')
  end
end
