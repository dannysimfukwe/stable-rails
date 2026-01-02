require 'spec_helper'

RSpec.describe Stable::Commands::Stop do
  it 'delegates to Services::AppStopper' do
    expect(Stable::Services::AppStopper).to receive(:new).with('app2').and_return(double(call: true))
    described_class.new('app2').call
  end
end
