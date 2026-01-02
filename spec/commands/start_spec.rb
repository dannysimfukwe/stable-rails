# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Start do
  it 'delegates to Services::AppStarter' do
    expect(Stable::Services::AppStarter).to receive(:new).with('app1').and_return(double(call: true))
    described_class.new('app1').call
  end
end
