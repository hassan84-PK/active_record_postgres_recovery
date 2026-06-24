# frozen_string_literal: true

require 'active_record/connection_adapters/postgresql_adapter'
require_relative 'handler'

module ActiveRecordPostgresRecovery
  module PostgresqlAdapterPatch
    SOURCE = 'ActiveRecord'
    QUERY_EXCEPTIONS = [ActiveRecord::StatementInvalid, PG::ConnectionBad].freeze
    RECONNECT_EXCEPTIONS = [ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad].freeze

    def execute_and_clear(sql, name, binds, prepare: false, async: false, &block)
      active_record_postgres_recovery_with_retry(sql, active_record_postgres_recovery_context(name)) do
        super
      end
    end

    def query(sql, name = nil)
      active_record_postgres_recovery_with_retry(sql, active_record_postgres_recovery_context(name)) do
        super
      end
    end

    def execute(sql, name = nil)
      active_record_postgres_recovery_with_retry(sql, active_record_postgres_recovery_context(name)) do
        super
      end
    end

    private

    def active_record_postgres_recovery_with_retry(sql, context)
      retry_count = 0
      recovery_error = nil

      begin
        result = yield
      rescue *QUERY_EXCEPTIONS => e
        raise unless ActiveRecordPostgresRecovery.configuration.enabled?
        raise unless Handler.db_connectivity_error?(e)

        if active_record_postgres_recovery_retryable_query?(sql, retry_count)
          retry_count += 1
          recovery_error = e
          active_record_postgres_recovery_reconnect!(context)
          retry
        end

        active_record_postgres_recovery_report_attempted!(context, recovery_error || e, retrying: retry_count.positive?)
        raise
      end

      active_record_postgres_recovery_report_successful(context, recovery_error) if recovery_error

      result
    end

    def active_record_postgres_recovery_reconnect!(context)
      reconnect!
    rescue *RECONNECT_EXCEPTIONS => e
      raise unless Handler.db_connectivity_error?(e)

      active_record_postgres_recovery_report_attempted!(context, e, retrying: true)
      raise
    end

    def active_record_postgres_recovery_report_attempted!(context, error, retrying:)
      clear_action = active_record_postgres_recovery_clear_connections!(error)

      Handler.report_attempted_recovery(
        context: context,
        error: error,
        retrying: retrying,
        source: SOURCE,
        clear_action: clear_action
      )
    end

    def active_record_postgres_recovery_report_successful(context, error)
      Handler.report_successful_recovery(context: context, error: error, source: SOURCE)
    end

    def active_record_postgres_recovery_retryable_query?(sql, retry_count)
      ActiveRecordPostgresRecovery.configuration.retry_read_queries? &&
        retry_count < ActiveRecordPostgresRecovery.configuration.max_retries &&
        !transaction_open? &&
        !write_query?(sql)
    rescue StandardError
      false
    end

    def active_record_postgres_recovery_context(name)
      "SQL #{name.respond_to?(:presence) ? name.presence : name || 'SQL'}"
    end

    def active_record_postgres_recovery_clear_connections!(error)
      if Handler.read_only_transaction_error?(error)
        Handler.clear_failover_connections!
      else
        Handler.clear_active_connections!
      end
    end
  end
end
