# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordPostgresRecovery::Handler do
  let(:handler) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionHandler) }
  let(:reported_events) { [] }

  before do
    ActiveRecordPostgresRecovery.configure do |config|
      config.reporter = ->(event) { reported_events << event }
    end
  end

  describe '.db_connectivity_error?' do
    it 'matches known PostgreSQL connection failures' do
      error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")

      expect(described_class.db_connectivity_error?(error)).to be(true)
    end

    it 'matches ActiveRecord connection-not-established failures' do
      error = ActiveRecord::ConnectionNotEstablished.new('connection is closed')

      expect(described_class.db_connectivity_error?(error)).to be(true)
    end

    it 'matches wrapped read-only transaction failures' do
      cause = StandardError.new('ERROR: cannot execute UPDATE in a read-only transaction')
      error = ActiveRecord::StatementInvalid.new('PG::ReadOnlySqlTransaction')
      allow(error).to receive(:cause).and_return(cause)

      expect(described_class.db_connectivity_error?(error)).to be(true)
    end

    it 'ignores unrelated SQL failures' do
      error = ActiveRecord::StatementInvalid.new('syntax error at or near "select"')

      expect(described_class.db_connectivity_error?(error)).to be(false)
    end
  end

  describe '.clear_active_connections!' do
    it 'clears configured roles' do
      allow(ActiveRecord::Base).to receive(:connection_handler).and_return(handler)
      expect(handler).to receive(:clear_active_connections!).with(:writing).ordered
      expect(handler).to receive(:clear_active_connections!).with(:reading).ordered

      expect(described_class.clear_active_connections!).to eq(
        strategy: 'active',
        performed: true,
        roles: %i[writing reading],
        skipped_reason: nil
      )
    end
  end

  describe '.clear_all_connections!' do
    it 'fully clears configured roles' do
      allow(ActiveRecord::Base).to receive(:connection_handler).and_return(handler)
      expect(handler).to receive(:clear_all_connections!).with(:writing).ordered
      expect(handler).to receive(:clear_all_connections!).with(:reading).ordered

      expect(described_class.clear_all_connections!).to eq(
        strategy: 'all',
        performed: true,
        roles: %i[writing reading],
        skipped_reason: nil
      )
    end
  end

  describe '.clear_failover_connections!' do
    it 'clears configured failover roles' do
      allow(ActiveRecord::Base).to receive(:connection_handler).and_return(handler)
      expect(handler).to receive(:clear_all_connections!).with(:writing)

      expect(described_class.clear_failover_connections!).to eq(
        strategy: 'failover_all',
        performed: true,
        roles: %i[writing],
        skipped_reason: nil
      )
    end
  end

  describe '.report_recovery' do
    it 'emits a structured recovery event' do
      error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")

      described_class.report_recovery(
        context: 'SQL Guest Load',
        error: error,
        retrying: true,
        source: 'ActiveRecord',
        outcome: :recovered
      )

      expect(reported_events.length).to eq(1)
      expect(reported_events.first.to_h).to include(
        outcome: :recovered,
        source: 'ActiveRecord',
        context: 'SQL Guest Load',
        retrying: true,
        matched_error_class: 'PG::ConnectionBad',
        matched_error_message: "PQsocket() can't get socket descriptor"
      )
    end

    it 'does not let reporter failures mask recovery behavior' do
      error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
      allow(ActiveRecordPostgresRecovery).to receive(:warn)

      ActiveRecordPostgresRecovery.configure do |config|
        config.reporter = ->(_event) { raise 'reporter unavailable' }
      end

      expect do
        described_class.report_recovery(
          context: 'SQL Guest Load',
          error: error,
          retrying: false,
          source: 'ActiveRecord',
          outcome: :attempted
        )
      end.not_to raise_error

      expect(ActiveRecordPostgresRecovery).to have_received(:warn).with(/reporter failed/)
    end
  end
end
