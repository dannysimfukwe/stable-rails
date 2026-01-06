# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Open do
  it 'delegates to Services::AppOpener' do
    expect(Stable::Services::AppOpener).to receive(:new).with('app').and_return(double(call: true))
    described_class.new('app').call
  end
end
