# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Setup do
  it 'delegates to Services::SetupRunner' do
    expect(Stable::Services::SetupRunner).to receive(:new).and_return(double(call: true))
    described_class.new.call
  end
end
