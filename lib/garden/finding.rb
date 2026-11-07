# frozen_string_literal: true

require "securerandom"
require "time"

module Garden
  # One issue found by a scan, and where it's got to.
  class Finding < Data.define(
    :id, :title, :details, :files, :severity, :status, :branch, :worktree, :pr_url, :reason, :rejected_at
  )
    # Most severe first.
    SEVERITIES = %w[high medium low].freeze
    STATUSES = %w[open fixing pending_review failed approved rejected].freeze
    # Has a branch or PR, so a rescan must keep it.
    IN_PROGRESS = %w[fixing pending_review failed approved].freeze
    # Waiting in the `garden review` queue.
    REVIEWABLE = %w[pending_review failed].freeze

    def self.build(title:, details: nil, files: [], severity: "medium")
      new(id: SecureRandom.hex(3), title: title, details: details, files: files,
          severity: severity, status: "open")
    end

    def self.from_h(hash)
      attrs = hash.transform_keys(&:to_sym).slice(*members)
      attrs[:rejected_at] = parse_time(attrs[:rejected_at])
      new(**attrs)
    end

    def self.parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : value
    end

    def initialize(id:, title:, status:, details: nil, files: [], severity: "medium", branch: nil,
                   worktree: nil, pr_url: nil, reason: nil, rejected_at: nil)
      raise Error, "Unknown finding status '#{status}'" unless STATUSES.include?(status)
      raise Error, "Unknown severity '#{severity}'" unless SEVERITIES.include?(severity)

      super
    end

    def in_progress? = IN_PROGRESS.include?(status)
    def reviewable? = REVIEWABLE.include?(status)

    def to_h
      super.transform_keys(&:to_s).merge("rejected_at" => rejected_at&.utc&.iso8601)
    end
  end
end
