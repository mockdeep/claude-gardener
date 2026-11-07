# frozen_string_literal: true

require "fileutils"
require "time"
require "yaml"

module Garden
  # A project's saved findings and when it was last scanned.
  class State
    WEEK = 7 * 24 * 60 * 60
    SCAN_MAX_AGE = WEEK
    REJECTION_TTL = WEEK

    attr_reader :scanned_at, :findings

    def self.from_h(hash)
      new(
        scanned_at: Finding.parse_time(hash["scanned_at"]),
        findings: (hash["findings"] || []).map { |f| Finding.from_h(f) }
      )
    end

    def initialize(scanned_at: nil, findings: [])
      @scanned_at = scanned_at
      @findings = findings
    end

    def to_h
      { "scanned_at" => scanned_at&.utc&.iso8601, "findings" => findings.map(&:to_h) }
    end

    def scan_stale?(now = Time.now)
      scanned_at.nil? || now - scanned_at > SCAN_MAX_AGE
    end

    # Swaps the open findings for a new scan's results. Findings with a
    # branch, PR, or rejection are kept.
    def record_scan(new_findings, now: Time.now)
      @findings = findings.reject { |f| f.status == "open" } + new_findings
      @scanned_at = now
    end

    def open_findings = findings.select { |f| f.status == "open" }

    # Open findings, most severe first, otherwise in the order found.
    def fix_queue
      open_findings.each_with_index
                   .sort_by { |f, i| [Finding::SEVERITIES.index(f.severity), i] }
                   .map(&:first)
    end
    def in_progress = findings.select(&:in_progress?)
    def review_queue = findings.select(&:reviewable?)
    def rejections = findings.select { |f| f.status == "rejected" }

    def find(id)
      findings.find { |f| f.id == id } or raise Error, "No finding with id #{id}"
    end

    def update(id, **attrs)
      updated = find(id).with(**attrs)
      @findings = findings.map { |f| f.id == id ? updated : f }
      updated
    end

    def reject(id, reason:, now: Time.now)
      update(id, status: "rejected", reason: reason, rejected_at: now)
    end

    def remove(id)
      find(id)
      @findings = findings.reject { |f| f.id == id }
    end

    # Drops rejections older than REJECTION_TTL.
    def prune(now = Time.now)
      @findings = findings.reject do |f|
        f.status == "rejected" && f.rejected_at && now - f.rejected_at > REJECTION_TTL
      end
    end
  end

  # Reads and writes a project's state file.
  class StateStore
    def initialize(project_name, dir: Paths.state_dir)
      @path = File.join(dir, "#{project_name}.yml")
    end

    attr_reader :path

    def read
      return State.new unless File.exist?(path)

      State.from_h(YAML.safe_load_file(path, permitted_classes: [Time]) || {})
    end

    # Locks the file, yields the current state, then saves it. Returns the
    # block's result. Don't nest calls for the same project: the inner one
    # will wait forever for the lock.
    def update
      FileUtils.mkdir_p(File.dirname(path))
      File.open("#{path}.lock", File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        state = read
        result = yield state
        write(state)
        result
      end
    end

    private

    # Write to a temp file and rename, so a crash can't leave half a file.
    def write(state)
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, YAML.dump(state.to_h))
      File.rename(tmp, path)
    end
  end
end
