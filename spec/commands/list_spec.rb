require 'spec_helper'

RSpec.describe Stable::Commands::List do
  it 'prints no apps when none registered' do
    allow(Stable::Services::AppRegistry).to receive(:all).and_return([])
    expect { described_class.new.call }.to output(/No apps registered/).to_stdout
  end

  it 'prints a header and app rows when apps present' do
    app = { name: 'x', domain: 'x.test', port: 3000, ruby: '3.0.0', started_at: nil }
    allow(Stable::Services::AppRegistry).to receive(:all).and_return([app])
    out = StringIO.new
    $stdout = out
    begin
      described_class.new.call
    ensure
      $stdout = STDOUT
    end

    output = out.string
    expect(output).to include('APP')
    expect(output).to include('x.test')
  end
end
