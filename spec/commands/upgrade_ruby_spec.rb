# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::UpgradeRuby do
  it 'delegates to Services::AppUpgrader' do
    expect(Stable::Services::AppUpgrader).to receive(:new).with('app', '3.4.4').and_return(double(call: true))
    described_class.new('app', '3.4.4').call
  end
end
