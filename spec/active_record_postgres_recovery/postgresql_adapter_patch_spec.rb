# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordPostgresRecovery::PostgresqlAdapterPatch do
  let(:all_clear_action) { { strategy: 'all', performed: true, roles: %i[writing reading], skipped_reason: nil } }
  let(:failover_clear_action) { { strategy: 'failover_all', performed: true, roles: %i[writing], skipped_reason: nil } }

  let(:adapter_class) do
    Class.new do
      prepend ActiveRecordPostgresRecovery::PostgresqlAdapterPatch

      attr_reader :calls, :reconnects

      def initialize(error_sequence: [], reconnect_error: nil)
        @error_sequence = error_sequence.dup
        @reconnect_error = reconnect_error
        @calls = 0
        @reconnects = 0
      end

      def execute_and_clear(_sql, _name, *_args, **_kwargs)
        perform_call
      end

      def query(_sql, _name = nil, *_args, **_kwargs)
        perform_call
      end

      def execute(_sql, _name = nil, *_args, **_kwargs)
        perform_call
      end

      def reconnect!
        @reconnects += 1
        raise @reconnect_error if @reconnect_error
      end

      def transaction_open?
        false
      end

      def write_query?(sql)
        !sql.to_s.lstrip.upcase.start_with?('SELECT')
      end

      private

      def perform_call
        @calls += 1
        error = @error_sequence.shift
        raise error if error

        :ok
      end
    end
  end

  before do
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:clear_all_connections!).and_return(all_clear_action)
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:clear_failover_connections!).and_return(failover_clear_action)
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:report_attempted_recovery)
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:report_successful_recovery)
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:read_only_transaction_error?).and_call_original
  end

  it 'accepts additional ActiveRecord adapter keywords when prepended' do
    expect(adapter_class.instance_method(:execute).parameters).to include([:keyrest])
    expect(adapter_class.instance_method(:execute_and_clear).parameters).to include([:keyrest])
    expect(adapter_class.instance_method(:query).parameters).to include([:keyrest])
  end

  it 'retries a read-only query once after a matched db connectivity error' do
    pg_error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
    statement_error = ActiveRecord::StatementInvalid.new('statement failed')
    allow(statement_error).to receive(:cause).and_return(pg_error)
    adapter = adapter_class.new(error_sequence: [statement_error])

    result = adapter.execute_and_clear('SELECT 1', 'Guest Load', [], prepare: false, async: false)

    expect(result).to eq(:ok)
    expect(adapter.calls).to eq(2)
    expect(adapter.reconnects).to eq(1)
    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:report_successful_recovery).with(
      context: 'SQL Guest Load',
      error: statement_error,
      source: 'ActiveRecord',
      clear_action: all_clear_action
    ).once
  end

  it 'forwards additional adapter keywords without raising' do
    adapter = adapter_class.new

    result = adapter.execute_and_clear(
      'SELECT 1',
      'Guest Load',
      [],
      prepare: false,
      async: false,
      allow_retry: true,
      materialize_transactions: false
    )

    expect(result).to eq(:ok)
    expect(adapter.calls).to eq(1)
  end

  it 'recovers from an initial ActiveRecord connection-not-established error' do
    error = ActiveRecord::ConnectionNotEstablished.new("PQsocket() can't get socket descriptor")
    adapter = adapter_class.new(error_sequence: [error])

    result = adapter.execute('SELECT 1', 'Guest Load')

    expect(result).to eq(:ok)
    expect(adapter.calls).to eq(2)
    expect(adapter.reconnects).to eq(1)
    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:clear_all_connections!).once
  end

  it 'uses configured max_retries for retryable read queries' do
    ActiveRecordPostgresRecovery.configure { |config| config.max_retries = 2 }
    errors = Array.new(2) { PG::ConnectionBad.new("PQsocket() can't get socket descriptor") }
    adapter = adapter_class.new(error_sequence: errors)

    result = adapter.execute('SELECT 1', 'Guest Load')

    expect(result).to eq(:ok)
    expect(adapter.calls).to eq(3)
    expect(adapter.reconnects).to eq(2)
  end

  it 'does not retry read queries when retry_read_queries is disabled' do
    ActiveRecordPostgresRecovery.configure { |config| config.retry_read_queries = false }
    error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
    adapter = adapter_class.new(error_sequence: [error])

    expect do
      adapter.execute('SELECT 1', 'Guest Load')
    end.to raise_error(PG::ConnectionBad, /PQsocket\(\) can't get socket descriptor/)

    expect(adapter.reconnects).to eq(0)
    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:report_attempted_recovery).with(
      context: 'SQL Guest Load',
      error: error,
      retrying: false,
      source: 'ActiveRecord',
      clear_action: all_clear_action
    ).once
  end

  it 'bypasses recovery when disabled with an environment-style false value' do
    ActiveRecordPostgresRecovery.configure { |config| config.enabled = 'false' }
    error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
    adapter = adapter_class.new(error_sequence: [error])

    expect do
      adapter.execute('SELECT 1', 'Guest Load')
    end.to raise_error(PG::ConnectionBad, /PQsocket\(\) can't get socket descriptor/)

    expect(adapter.reconnects).to eq(0)
    expect(ActiveRecordPostgresRecovery::Handler).not_to have_received(:report_attempted_recovery)
  end

  it 'clears all configured connections and re-raises matched write query errors' do
    error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
    adapter = adapter_class.new(error_sequence: [error])

    expect do
      adapter.execute('UPDATE guests SET first_name = 1', 'Guest Update')
    end.to raise_error(PG::ConnectionBad, /PQsocket\(\) can't get socket descriptor/)

    expect(adapter.reconnects).to eq(0)
    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:report_attempted_recovery).with(
      context: 'SQL Guest Update',
      error: error,
      retrying: false,
      source: 'ActiveRecord',
      clear_action: all_clear_action
    ).once
  end

  it 'reports attempted recovery once when reconnect fails after clearing the pool' do
    error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
    reconnect_error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")
    adapter = adapter_class.new(error_sequence: [error], reconnect_error: reconnect_error)

    expect do
      adapter.execute('SELECT 1', 'Guest Load')
    end.to raise_error(PG::ConnectionBad, /PQsocket\(\) can't get socket descriptor/)

    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:clear_all_connections!).once
    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:report_attempted_recovery).with(
      context: 'SQL Guest Load',
      error: reconnect_error,
      retrying: true,
      source: 'ActiveRecord',
      clear_action: all_clear_action
    ).once
  end

  it 'uses failover clearing for read-only transaction errors' do
    pg_error = StandardError.new('ERROR: cannot execute UPDATE in a read-only transaction')
    statement_error = ActiveRecord::StatementInvalid.new('PG::ReadOnlySqlTransaction')
    allow(statement_error).to receive(:cause).and_return(pg_error)
    adapter = adapter_class.new(error_sequence: [statement_error])

    expect do
      adapter.execute('UPDATE active_storage_blobs SET metadata = metadata', 'ActiveStorage::AnalyzeJob')
    end.to raise_error(ActiveRecord::StatementInvalid, 'PG::ReadOnlySqlTransaction')

    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:report_attempted_recovery).with(
      context: 'SQL ActiveStorage::AnalyzeJob',
      error: statement_error,
      retrying: false,
      source: 'ActiveRecord',
      clear_action: failover_clear_action
    ).once
  end
end
