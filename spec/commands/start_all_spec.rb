# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::StartAll do
  it 'delegates to Services::AppStarterAll' do
    expect(Stable::Services::AppStarterAll).to receive(:new).and_return(double(call: true))
    described_class.new.call
  end
end
