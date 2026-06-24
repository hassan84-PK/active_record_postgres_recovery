# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordPostgresRecovery::SidekiqMiddleware do
  let(:middleware) { described_class.new }
  let(:worker) { Class.new.new }
  let(:job) { { 'jid' => 'jid-123' } }
  let(:queue) { 'default' }
  let(:clear_action) { { strategy: 'active', performed: true, roles: %i[writing reading], skipped_reason: nil } }

  before do
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:report_attempted_recovery)
    allow(ActiveRecordPostgresRecovery::Handler).to receive(:clear_active_connections!).and_return(clear_action)
  end

  it 'clears active connections and re-raises matching db connectivity errors' do
    error = PG::ConnectionBad.new("PQsocket() can't get socket descriptor")

    expect do
      middleware.call(worker, job, queue) { raise error }
    end.to raise_error(PG::ConnectionBad, /PQsocket\(\) can't get socket descriptor/)

    expect(ActiveRecordPostgresRecovery::Handler).to have_received(:report_attempted_recovery).with(
      context: "Sidekiq #{worker.class.name} jid=jid-123 queue=default",
      error: error,
      source: 'Sidekiq',
      clear_action: clear_action
    ).once
  end

  it 'does not clear connections for unrelated errors' do
    expect do
      middleware.call(worker, job, queue) { raise ActiveRecord::StatementInvalid, 'syntax error at or near "select"' }
    end.to raise_error(ActiveRecord::StatementInvalid, 'syntax error at or near "select"')

    expect(ActiveRecordPostgresRecovery::Handler).not_to have_received(:clear_active_connections!)
  end
end
