# frozen_string_literal: true

require_relative 'active_record_postgres_recovery/version'
require_relative 'active_record_postgres_recovery/configuration'

module ActiveRecordPostgresRecovery
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def report(event)
      configuration.reporter&.call(event)
    rescue StandardError => e
      report_reporter_failure(e, event)
      nil
    end

    private

    def report_reporter_failure(error, event)
      message = "[active_record_postgres_recovery] reporter failed with #{error.class}: #{error.message} while reporting #{event.outcome} from #{event.source}"

      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end
  end
end

require_relative 'active_record_postgres_recovery/railtie' if defined?(Rails::Railtie)
