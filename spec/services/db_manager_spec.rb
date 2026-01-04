# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Stable::DBManager do
  describe '#rails_config' do
    it 'returns postgres rails config' do
      db = described_class.new('mydb', adapter: :postgresql)
      cfg = db.rails_config
      expect(cfg['adapter']).to eq('postgresql')
      expect(cfg['database']).to eq('mydb')
      expect(cfg['username']).to eq(ENV['USER'] || 'stable')
    end

    it 'returns mysql rails config' do
      allow_any_instance_of(described_class).to receive(:mysql_socket).and_return('/tmp/mysql.sock')
      db = described_class.new('mydb2', adapter: :mysql)
      cfg = db.rails_config
      expect(cfg['adapter']).to eq('mysql2')
      expect(cfg['database']).to eq('mydb2')
      expect(cfg['socket']).to eq('/tmp/mysql.sock')
    end
  end

  describe '#create' do
    it 'creates postgres database when missing' do
      db = described_class.new('pgdb', adapter: :postgresql)

      allow_any_instance_of(Object).to receive(:system) do |_, cmd|
        if cmd =~ /psql -lqt/ # existence check
          false
        elsif cmd =~ /createdb/ # create command
          true
        else
          true
        end
      end

      expect { db.create }.not_to raise_error
    end

    it 'creates mysql database when root auth ok' do
      db = described_class.new('mysqldb', adapter: :mysql)
      allow_any_instance_of(described_class).to receive(:mysql_socket).and_return('/tmp/mysql.sock')

      allow_any_instance_of(Object).to receive(:system).and_return(true)

      expect { db.create }.not_to raise_error
    end

    it 'raises when createdb fails for postgres' do
      db = described_class.new('pgfail', adapter: :postgresql)
      allow_any_instance_of(Object).to receive(:system) do |_, cmd|
        if cmd =~ /psql -lqt/
          false
        elsif cmd =~ /createdb/
          false
        else
          true
        end
      end

      expect { db.create }.to raise_error(SystemExit)
    end

    it 'raises when mysql socket not found' do
      db = described_class.new('mysqlfail', adapter: :mysql)
      allow_any_instance_of(described_class).to receive(:mysql_socket).and_raise(SystemExit)

      expect { db.create }.to raise_error(SystemExit)
    end
  end
end
