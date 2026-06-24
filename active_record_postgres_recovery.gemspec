# frozen_string_literal: true

require_relative 'lib/active_record_postgres_recovery/version'

Gem::Specification.new do |spec|
  spec.name = 'active_record_postgres_recovery'
  spec.version = ActiveRecordPostgresRecovery::VERSION
  spec.authors = ['Hassan']
  spec.email = ['m.hassanror@gmail.com']

  spec.summary = 'Safe PostgreSQL connection recovery for Rails ActiveRecord apps.'
  spec.description = 'Retries safe read queries after stale PostgreSQL connection failures, clears ActiveRecord connection pools, and exposes recovery events for observability.'
  spec.homepage = 'https://github.com/your-github/active_record_postgres_recovery'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/releases"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*.rb', 'README.md', 'LICENSE.txt']
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 7.0', '< 8.0'
  spec.add_dependency 'activesupport', '>= 7.0', '< 8.0'
  spec.add_dependency 'pg', '>= 1.5', '< 2.0'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
end
