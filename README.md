# ActiveRecordPostgresRecovery

Safe PostgreSQL connection recovery for Rails apps using ActiveRecord.

This gem handles a narrow production failure mode: Rails still has a stale or invalid PostgreSQL connection after a deploy, AWS RDS PostgreSQL failover, restart, or network interruption. It can retry safe read queries once, clear affected ActiveRecord connection pools, and emit structured recovery events to your observability stack.

It does not hide database outages and it does not retry writes.

## Installation

Add this line to your Rails app Gemfile:

```ruby
gem 'active_record_postgres_recovery'
```

For local development from a sibling `gems/` directory:

```ruby
gem 'active_record_postgres_recovery', path: '../gems/active_record_postgres_recovery'
```

Then run:

```sh
bundle install
```

## Configuration

Create `config/initializers/active_record_postgres_recovery.rb`:

```ruby
ActiveRecordPostgresRecovery.configure do |config|
  config.enabled = true
  config.retry_read_queries = true
  config.max_retries = 1
  config.roles = %i[writing reading]
  config.failover_clear_roles = %i[writing]

  config.reporter = lambda do |event|
    Bugsnag.notify(event.matched_error) do |report|
      report.severity = 'warning'
      report.add_metadata(:active_record_postgres_recovery, event.to_h)
    end
  end
end
```

The reporter is optional. Without one, recovery still runs but events are not sent anywhere.

For production rollouts, prefer environment-backed switches so recovery can be disabled without a deploy:

```ruby
ActiveRecordPostgresRecovery.configure do |config|
  config.enabled = ENV.fetch('ACTIVE_RECORD_POSTGRES_RECOVERY_ENABLED', true)
  config.retry_read_queries = ENV.fetch('ACTIVE_RECORD_POSTGRES_RECOVERY_RETRY_READS', true)
  config.max_retries = ENV.fetch('ACTIVE_RECORD_POSTGRES_RECOVERY_MAX_RETRIES', 1)

  config.reporter = lambda do |event|
    Rails.logger.warn(
      event: 'active_record_postgres_recovery',
      recovery: event.to_h
    )
  end
end
```

### Options

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `true` | Enables recovery handling. When false, matching database errors are re-raised without recovery logic. |
| `reporter` | `nil` | Callable that receives a `RecoveryEvent`. Use this to send recovery data to Bugsnag, Datadog, logs, or metrics. |
| `roles` | `%i[writing reading]` | ActiveRecord roles cleared for normal stale connection errors. |
| `failover_clear_roles` | `%i[writing]` | ActiveRecord roles cleared when a read-only transaction error indicates a bad failover/write connection. |
| `retry_read_queries` | `true` | Enables one or more retries for safe read queries outside transactions. |
| `max_retries` | `1` | Maximum retry attempts for retryable read queries. Writes are still never retried. |
| `error_patterns` | PostgreSQL stale connection patterns | Regex list used to decide whether an exception is handled by this gem. |

You can append app-specific PostgreSQL errors if needed:

```ruby
ActiveRecordPostgresRecovery.configure do |config|
  config.error_patterns += [
    /server closed the connection unexpectedly/i
  ]
end
```

### Recovery Events

The reporter receives an event with these attributes:

| Attribute | Description |
| --- | --- |
| `outcome` | `:attempted` when recovery was attempted and the original error is re-raised, or `:recovered` after a retry succeeds. |
| `source` | Source of the recovery event, for example `ActiveRecord` or `Sidekiq`. |
| `context` | Query name or job context. |
| `error` | Original exception. |
| `matched_error` | Exception in the cause chain that matched `error_patterns`. |
| `retrying` | Whether the operation was retrying. |
| `clear_action` | Hash describing which connection pools were cleared. |

Use `event.to_h` for structured metadata safe to attach to observability tools.

## Sidekiq

If you want Sidekiq jobs to clear stale ActiveRecord connections before Sidekiq retries the job:

```ruby
require 'active_record_postgres_recovery/sidekiq_middleware'

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ActiveRecordPostgresRecovery::SidekiqMiddleware
  end
end
```

## Safety Rules

The adapter patch is intentionally conservative:

- A non-transactional read query may reconnect and retry once.
- Write queries are not retried automatically.
- Queries inside an open transaction are not retried automatically.
- Matching write or transaction failures clear affected connection pools, report the event, and re-raise.
- Read-only transaction errors clear the writing pool to force ActiveRecord away from a bad failover connection.

## Supported Scope

This gem is PostgreSQL-only and currently targets ActiveRecord 7.x.

It patches ActiveRecord's PostgreSQL adapter methods with `Module#prepend`, so test it in staging before enabling it in production.
