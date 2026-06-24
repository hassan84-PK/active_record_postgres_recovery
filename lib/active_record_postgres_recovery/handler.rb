# frozen_string_literal: true

require 'active_record'
require_relative 'recovery_event'

module ActiveRecordPostgresRecovery
  module Handler
    READ_ONLY_TRANSACTION_MESSAGE = /read-only transaction/i
    RECOVERY_REPORTED_IVAR = :@active_record_postgres_recovery_reported

    module_function

    def db_connectivity_error?(error)
      !matching_error(error).nil?
    end

    def clear_active_connections!
      roles = ActiveRecordPostgresRecovery.configuration.roles
      handler = ActiveRecord::Base.connection_handler
      roles.each { |role| handler.clear_active_connections!(role) }
      build_clear_action(strategy: 'active', performed: true, roles: roles)
    end

    def clear_all_connections!(roles: ActiveRecordPostgresRecovery.configuration.roles)
      handler = ActiveRecord::Base.connection_handler
      roles.each { |role| handler.clear_all_connections!(role) }
      build_clear_action(strategy: 'all', performed: true, roles: roles)
    end

    def clear_failover_connections!
      roles = ActiveRecordPostgresRecovery.configuration.failover_clear_roles
      clear_all_connections!(roles: roles).merge(
        build_clear_action(strategy: 'failover_all', performed: true, roles: roles)
      )
    end

    def read_only_transaction_error?(error)
      !find_error_in_chain(error) { |current| current.message.to_s.match?(READ_ONLY_TRANSACTION_MESSAGE) }.nil?
    end

    def report_attempted_recovery(context:, error:, source:, retrying: false, clear_action: nil)
      report_recovery(context: context, error: error, source: source, outcome: :attempted, retrying: retrying, clear_action: clear_action)
    end

    def report_successful_recovery(context:, error:, source:, clear_action: nil)
      report_recovery(context: context, error: error, source: source, outcome: :recovered, retrying: true, clear_action: clear_action)
    end

    def report_recovery(context:, error:, source:, outcome:, retrying: false, clear_action: nil)
      return if recovery_reported?(error)

      matched_error = matching_error(error) || error
      clear_action ||= build_clear_action(strategy: nil, performed: false, roles: [])

      ActiveRecordPostgresRecovery.report(
        RecoveryEvent.new(
          outcome: outcome,
          source: source,
          context: context,
          error: error,
          matched_error: matched_error,
          retrying: retrying,
          clear_action: clear_action
        )
      )

      mark_recovery_reported!(error)
    end

    def matching_error(error)
      find_error_in_chain(error) { |current| connection_error_message?(current.message) }
    end
    private_class_method :matching_error

    def connection_error_message?(message)
      ActiveRecordPostgresRecovery.configuration.error_patterns.any? { |pattern| message.to_s.match?(pattern) }
    end
    private_class_method :connection_error_message?

    def find_error_in_chain(error)
      current = error

      while current
        return current if yield(current)

        current = current.cause
      end

      nil
    end
    private_class_method :find_error_in_chain

    def build_clear_action(strategy:, performed:, roles:, skipped_reason: nil)
      {
        strategy: strategy,
        performed: performed,
        roles: roles,
        skipped_reason: skipped_reason
      }
    end
    private_class_method :build_clear_action

    def recovery_reported?(error)
      error.instance_variable_defined?(RECOVERY_REPORTED_IVAR) &&
        error.instance_variable_get(RECOVERY_REPORTED_IVAR)
    end
    private_class_method :recovery_reported?

    def mark_recovery_reported!(error)
      error.instance_variable_set(RECOVERY_REPORTED_IVAR, true)
    rescue FrozenError
      nil
    end
    private_class_method :mark_recovery_reported!
  end
end
