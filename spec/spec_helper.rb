# frozen_string_literal: true

require 'active_record_postgres_recovery'
require 'active_record_postgres_recovery/handler'
require 'active_record_postgres_recovery/postgresql_adapter_patch'
require 'active_record_postgres_recovery/sidekiq_middleware'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }

  config.before do
    ActiveRecordPostgresRecovery.configuration = ActiveRecordPostgresRecovery::Configuration.new
  end
end
