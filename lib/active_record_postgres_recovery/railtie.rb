# frozen_string_literal: true

require 'rails/railtie'
require_relative 'postgresql_adapter_patch'

module ActiveRecordPostgresRecovery
  class Railtie < Rails::Railtie
    initializer 'active_record_postgres_recovery.patch_postgresql_adapter' do
      ActiveSupport.on_load(:active_record) do
        adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
        next if adapter.ancestors.include?(ActiveRecordPostgresRecovery::PostgresqlAdapterPatch)

        adapter.prepend(ActiveRecordPostgresRecovery::PostgresqlAdapterPatch)
      end
    end
  end
end
