# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordPostgresRecovery::Configuration do
  describe '#enabled=' do
    it 'normalizes common false values' do
      config = described_class.new

      ['false', '0', 'no', 'off', false, nil, 0].each do |value|
        config.enabled = value

        expect(config).not_to be_enabled
      end
    end

    it 'treats other values as enabled' do
      config = described_class.new

      ['true', '1', 'yes', true, 1].each do |value|
        config.enabled = value

        expect(config).to be_enabled
      end
    end
  end

  describe '#retry_read_queries=' do
    it 'normalizes common false values' do
      config = described_class.new

      config.retry_read_queries = 'false'

      expect(config).not_to be_retry_read_queries
    end
  end

  describe '#max_retries=' do
    it 'coerces numeric strings to integers' do
      config = described_class.new

      config.max_retries = '2'

      expect(config.max_retries).to eq(2)
    end

    it 'clamps negative values to zero' do
      config = described_class.new

      config.max_retries = -1

      expect(config.max_retries).to eq(0)
    end

    it 'rejects non-integer values' do
      config = described_class.new

      expect { config.max_retries = 'many' }.to raise_error(ArgumentError, /max_retries/)
    end
  end

  describe 'roles' do
    it 'normalizes strings to symbols' do
      config = described_class.new

      config.roles = %w[writing reading]
      config.failover_clear_roles = ['writing']

      expect(config.roles).to eq(%i[writing reading])
      expect(config.failover_clear_roles).to eq(%i[writing])
    end
  end
end
