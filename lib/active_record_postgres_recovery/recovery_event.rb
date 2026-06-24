# frozen_string_literal: true

module ActiveRecordPostgresRecovery
  RecoveryEvent = Struct.new(
    :outcome,
    :source,
    :context,
    :error,
    :matched_error,
    :retrying,
    :clear_action,
    keyword_init: true
  ) do
    def to_h
      {
        outcome: outcome,
        source: source,
        context: context,
        retrying: retrying,
        clear_strategy: clear_action[:strategy],
        clear_performed: clear_action[:performed],
        cleared_roles: clear_action[:roles],
        clear_skipped_reason: clear_action[:skipped_reason],
        matched_error_class: matched_error.class.name,
        matched_error_message: matched_error.message.to_s.lines.first.to_s.strip
      }
    end
  end
end
