# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Commands::New do
  it 'delegates to Services::AppCreator' do
    expect(Stable::Services::AppCreator).to receive(:new).with('appname', kind_of(Hash)).and_return(double(call: true))
    described_class.new('appname', {}).call
  end
end
