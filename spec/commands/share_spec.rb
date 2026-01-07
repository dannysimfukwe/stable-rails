# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Share do
  let(:app) { { name: 'myapp', port: 3001, pid: 12_345 } }

  before do
    ENV['STABLE_TEST_MODE'] = 'true'
    allow(Stable::Services::AppRegistry).to receive(:find).and_return(app)
  end

  after { ENV.delete('STABLE_TEST_MODE') }

  it 'prints the shared URL' do
    expect do
      described_class.new('myapp').call
    end.to output(%r{https://3001-stable-share\.test}).to_stdout
  end
end
