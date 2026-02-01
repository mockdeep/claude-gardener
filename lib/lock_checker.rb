# frozen_string_literal: true

require "set"

module ClaudeGardener
  class LockChecker
    def initialize(github:, config:)
      @github = github
      @config = config
    end

    def locked_files
      gardener_prs = @github.pull_requests(
        state: "open",
        labels: [@config.labels.base]
      )

      locked = Set.new

      gardener_prs.each do |pr|
        files = @github.pull_request_files(pr.number)
        files.each { |file| locked.add(file.filename) }
      end

      locked
    end

    def file_locked?(filename)
      locked_files.include?(filename)
    end

    def any_locked?(filenames)
      locks = locked_files
      filenames.any? { |f| locks.include?(f) }
    end
  end
end
