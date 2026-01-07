# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Stable::Services::Tunneling::Manager do
  describe '#initialize' do
    it 'sets the provider' do
      manager = described_class.new(provider: :ngrok)
      expect(manager.instance_variable_get(:@provider)).to eq(:ngrok)
    end
  end

  describe '#expose_domain' do
    context 'with ngrok provider' do
      let(:manager) { described_class.new(provider: :ngrok) }
      let(:mock_adapter) { instance_double(Stable::Services::Tunneling::Providers::Ngrok) }

      before do
        allow(Stable::Services::Tunneling::Providers::Ngrok).to receive(:new).and_return(mock_adapter)
        allow(mock_adapter).to receive(:expose)
      end

      it 'calls expose on the ngrok adapter' do
        manager.expose_domain('example.test', port: 3000, skip_ssl: false)
        expect(mock_adapter).to have_received(:expose).with('example.test', port: 3000, skip_ssl: false)
      end
    end

    context 'with stable provider' do
      let(:manager) { described_class.new(provider: :stable) }
      let(:mock_adapter) { instance_double(Stable::Services::Tunneling::Providers::Stable) }

      before do
        allow(Stable::Services::Tunneling::Providers::Stable).to receive(:new).and_return(mock_adapter)
        allow(mock_adapter).to receive(:expose)
      end

      it 'calls expose on the stable adapter' do
        manager.expose_domain('example.test', port: 3000, skip_ssl: false)
        expect(mock_adapter).to have_received(:expose).with('example.test', port: 3000, skip_ssl: false)
      end
    end

    context 'with unknown provider' do
      let(:manager) { described_class.new(provider: :unknown) }

      it 'aborts with error message' do
        expect { manager.expose_domain('example.test', port: 3000) }.to raise_error(SystemExit, 'Unknown tunnel provider: unknown')
      end
    end
  end
end
