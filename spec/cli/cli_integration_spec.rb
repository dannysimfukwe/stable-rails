# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::CLI do
  let(:cli) { described_class.new }

  it 'delegates list to Commands::List' do
    cmd = instance_double('Commands::List', call: true)
    allow(Commands::List).to receive(:new).and_return(cmd)

    expect(cmd).to receive(:call)
    cli.list
  end

  it 'delegates new to Commands::New' do
    cmd = instance_double('Commands::New', call: true)
    allow(Commands::New).to receive(:new).with('myapp', anything).and_return(cmd)

    expect(cmd).to receive(:call)
    cli.new('myapp')
  end
end
