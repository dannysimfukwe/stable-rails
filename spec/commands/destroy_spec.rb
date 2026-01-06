# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Destroy do
  it 'delegates to Services::Destroy' do
    expect(Stable::Services::AppDestroyer).to receive(:new).with('app').and_return(double(call: true))
    described_class.new('app').call
  end
end
