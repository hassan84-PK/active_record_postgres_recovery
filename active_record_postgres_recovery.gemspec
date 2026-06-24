# frozen_string_literal: true

require_relative 'lib/active_record_postgres_recovery/version'

Gem::Specification.new do |spec|
  github_repo = 'https://github.com/hassan84-PK/active_record_postgres_recovery'

  spec.name = 'active_record_postgres_recovery'
  spec.version = ActiveRecordPostgresRecovery::VERSION
  spec.authors = ['Hassan']
  spec.email = ['m.hassanror@gmail.com']

  spec.summary = 'Rails PostgreSQL failover recovery for ActiveRecord apps on AWS RDS, Aurora, and PostgreSQL.'
  spec.description = 'Recovers from stale ActiveRecord PostgreSQL connections after AWS RDS or Aurora failover, deploys, restarts, and network interruptions by retrying safe reads, clearing pools, and reporting recovery events.'
  spec.homepage = github_repo
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = github_repo
  spec.metadata['bug_tracker_uri'] = "#{github_repo}/issues"
  spec.metadata['documentation_uri'] = "#{github_repo}#readme"
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
