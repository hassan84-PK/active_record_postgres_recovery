# frozen_string_literal: true

require_relative 'handler'

module ActiveRecordPostgresRecovery
  class SidekiqMiddleware
    SOURCE = 'Sidekiq'

    def call(worker, job, queue)
      yield
    rescue StandardError => e
      raise unless ActiveRecordPostgresRecovery.configuration.enabled?
      raise unless Handler.db_connectivity_error?(e)

      clear_action = if Handler.read_only_transaction_error?(e)
                       Handler.clear_failover_connections!
                     else
                       Handler.clear_active_connections!
                     end
      Handler.report_attempted_recovery(
        context: sidekiq_context(worker, job, queue),
        error: e,
        source: SOURCE,
        clear_action: clear_action
      )
      raise
    end

    private

    def sidekiq_context(worker, job, queue)
      "Sidekiq #{worker.class.name} jid=#{job['jid']} queue=#{queue}"
    end
  end
end
