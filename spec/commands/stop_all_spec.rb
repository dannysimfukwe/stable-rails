# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::StopAll do
  it 'delegates to Services::AppStopperAll' do
    expect(Stable::Services::AppStopperAll).to receive(:new).and_return(double(call: true))
    described_class.new.call
  end
end
