# frozen_string_literal: true

module ActiveRecordPostgresRecovery
  class Configuration
    BOOLEAN_FALSE_VALUES = [false, nil, 'false', 'FALSE', '0', 0, 'no', 'NO', 'off', 'OFF'].freeze

    attr_accessor :reporter, :error_patterns
    attr_reader :enabled, :roles, :failover_clear_roles, :retry_read_queries, :max_retries

    def initialize
      self.enabled = true
      @reporter = nil
      self.roles = %i[writing reading]
      self.failover_clear_roles = %i[writing]
      self.retry_read_queries = true
      self.max_retries = 1
      @error_patterns = [
        /PQconsumeInput\(\).*terminating connection due to administrator command.*SSL connection has been closed unexpectedly/im,
        /PQsocket\(\) can't get socket descriptor/i,
        /read-only transaction/i
      ]
    end

    def enabled=(value)
      @enabled = boolean(value)
    end

    def enabled?
      enabled
    end

    def retry_read_queries=(value)
      @retry_read_queries = boolean(value)
    end

    def retry_read_queries?
      retry_read_queries
    end

    def max_retries=(value)
      @max_retries = [Integer(value), 0].max
    rescue ArgumentError, TypeError
      raise ArgumentError, 'max_retries must be an integer greater than or equal to 0'
    end

    def roles=(value)
      @roles = normalize_roles(value)
    end

    def failover_clear_roles=(value)
      @failover_clear_roles = normalize_roles(value)
    end

    private

    def boolean(value)
      !BOOLEAN_FALSE_VALUES.include?(value)
    end

    def normalize_roles(value)
      Array(value).map(&:to_sym)
    end
  end
end
