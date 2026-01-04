# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::Services::AppRegistry do
  it 'adds, finds, updates and removes apps' do
    expect(Stable::Registry.apps).to be_empty

    app = { name: 'foo', path: '/tmp/foo', domain: 'foo.test', port: 3001 }
    described_class.add(app)

    expect(described_class.find('foo')[:path]).to eq('/tmp/foo')
    expect(described_class.all.map { |a| a[:name] }).to include('foo')

    described_class.update('foo', port: 4000)
    expect(described_class.find('foo')[:port]).to eq(4000)

    described_class.remove('foo')
    expect(described_class.find('foo')).to be_nil
  end

  it 'registers a new app and allocates a port' do
    app = described_class.register('bar')
    expect(app[:name]).to eq('bar')
    expect(app[:port]).to be_a(Integer)
    expect(described_class.find('bar')[:name]).to eq('bar')
  end

  it 'overwrites existing app when adding with same name' do
    app1 = { name: 'baz', path: '/tmp/baz1', domain: 'baz.test', port: 3001 }
    app2 = { name: 'baz', path: '/tmp/baz2', domain: 'baz.test', port: 3002 }

    described_class.add(app1)
    expect(described_class.find('baz')[:path]).to eq('/tmp/baz1')

    described_class.add(app2)
    expect(described_class.find('baz')[:path]).to eq('/tmp/baz2')
  end
end
