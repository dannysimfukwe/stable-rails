# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::Restart do
  it 'delegates to Services::AppRestarter' do
    expect(Stable::Services::AppRestarter).to receive(:new).with('app3').and_return(double(call: true))
    described_class.new('app3').call
  end
end
