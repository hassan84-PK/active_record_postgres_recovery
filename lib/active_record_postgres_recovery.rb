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
    end
  end
end

require_relative 'active_record_postgres_recovery/railtie' if defined?(Rails::Railtie)
