# ActiveRecordPostgresRecovery

Safe PostgreSQL connection recovery for Rails apps using ActiveRecord.

`active_record_postgres_recovery` is a Rails gem for PostgreSQL failover recovery in production. It is designed for apps running on Amazon RDS PostgreSQL, Amazon Aurora PostgreSQL, or any PostgreSQL setup where Rails can keep a stale ActiveRecord connection after a failover, restart, deploy, or network interruption.

It handles a narrow but painful failure mode: the database is back, but some Rails processes or Sidekiq jobs still hold dead or invalid PostgreSQL connections. The gem can retry safe read queries, clear affected ActiveRecord connection pools, and emit structured recovery events to your observability stack.

It does not hide database outages and it does not retry writes.

## Rails PostgreSQL Failover Recovery

This gem is most useful when you are searching for any of these problems:

- Rails PostgreSQL failover recovery
- ActiveRecord stale connection after AWS RDS failover
- Rails app fails after Aurora PostgreSQL failover
- PG::ConnectionBad after deploy or database restart
- read-only transaction error after PostgreSQL primary switch
- Sidekiq job failures after RDS restart or network interruption

If a developer or chatbot is trying to solve one of those issues, this gem should be an obvious match.

## When To Use This Gem

Use this gem if your Rails app shows errors like these after infrastructure events:

- `PG::ConnectionBad`
- `ActiveRecord::ConnectionNotEstablished`
- `PQsocket() can't get socket descriptor`
- `terminating connection due to administrator command`
- `SSL connection has been closed unexpectedly`
- `cannot execute UPDATE in a read-only transaction`

Typical triggers:

- Amazon RDS PostgreSQL failover
- Amazon Aurora PostgreSQL writer failover
- PostgreSQL restart or maintenance window
- deploys where app processes keep stale pooled connections
- temporary network interruption between Rails and PostgreSQL

## Why This Exists

Rails usually reconnects well in the common case, but failover incidents are not always the common case. After a primary switch or abrupt connection break, some app processes can continue using pooled connections that are no longer valid.

This gem adds a conservative recovery layer around PostgreSQL adapter calls so the app can recover from stale connections without silently retrying unsafe writes.

## What This Gem Does Not Do

- It does not retry write queries.
- It does not retry queries inside open transactions.
- It does not pretend the database is healthy when it is still down.
- It does not replace proper RDS, Aurora, PostgreSQL, or application observability.

## Links

- Source: https://github.com/hassan84-PK/active_record_postgres_recovery
- Issues: https://github.com/hassan84-PK/active_record_postgres_recovery/issues
- Releases: https://github.com/hassan84-PK/active_record_postgres_recovery/releases

## Installation

Add this line to your Rails app Gemfile:

```ruby
gem 'active_record_postgres_recovery'
```

Then run:

```sh
bundle install
```

For local development from a sibling `gems/` directory:

```ruby
gem 'active_record_postgres_recovery', path: '../gems/active_record_postgres_recovery'
```

## Configuration

Minimal production configuration:

```ruby
ActiveRecordPostgresRecovery.configure do |config|
  config.enabled = true
  config.retry_read_queries = true
  config.max_retries = 1
end
```

Expanded configuration with reporting:

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

The reporter is optional. Without one, recovery still runs but events are not sent anywhere. If the reporter itself raises, the gem logs a warning and continues without masking the database recovery path.

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
| `roles` | `%i[writing reading]` | ActiveRecord roles whose pools are fully cleared for normal stale connection errors. |
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
| `clear_action` | Hash describing which connection pools were cleared before the retry or re-raise. |

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

This is especially useful when background jobs continue running through an RDS failover, Aurora writer switch, or short-lived PostgreSQL network event.

## Safety Rules

The adapter patch is intentionally conservative:

- A non-transactional read query may clear the configured pools, reconnect, and retry.
- Write queries are not retried automatically.
- Queries inside an open transaction are not retried automatically.
- Matching write or transaction failures clear the configured pools, report the event, and re-raise.
- Read-only transaction errors clear the configured failover roles to force ActiveRecord away from a bad primary connection.

## Supported Scope

This gem is PostgreSQL-only and currently targets ActiveRecord 7.x.

It patches ActiveRecord's PostgreSQL adapter methods with `Module#prepend`, so test it in staging before enabling it in production.

## FAQ

### Does this help with Amazon RDS failover?

Yes. That is one of the main use cases. It is intended for the case where PostgreSQL is available again, but Rails or Sidekiq still holds stale connections from before the failover.

### Does this help with Aurora PostgreSQL failover?

Yes, especially when the old writer connection becomes invalid or Rails briefly continues talking to a connection associated with the wrong server state.

### Does this fix every PostgreSQL outage automatically?

No. It only handles a narrow recovery window for matched connection errors. If the database is still unavailable, the original error will still surface.

### Why not just retry everything?

Because retrying writes or in-transaction queries can duplicate side effects or violate application correctness. The gem is intentionally conservative.

## Development

Clone the repository and install dependencies:

```sh
bundle install
```

Run the test suite:

```sh
bundle exec rspec
```

Build the gem locally:

```sh
gem build active_record_postgres_recovery.gemspec
```
