# frozen_string_literal: true

require "yaml"

module ClaudeGardener
  class Config
    DEFAULT_CATEGORIES = %w[
      test_coverage
      security_fixes
      linter_fixes
      code_improvements
    ].freeze

    DEFAULT_CONFIG = {
      "version" => 1,
      "workers" => { "max_concurrent" => 3 },
      "priorities" => [
        { "category" => "test_coverage", "max_prs" => 3, "enabled" => true },
        { "category" => "security_fixes", "max_prs" => 2, "enabled" => true },
        { "category" => "linter_fixes", "max_prs" => 5, "enabled" => true },
        { "category" => "code_improvements", "max_prs" => 3, "enabled" => true }
      ],
      "guardrails" => {
        "max_iterations_per_pr" => 5,
        "max_files_per_pr" => 10,
        "require_tests" => true
      },
      "labels" => {
        "base" => "claude-gardener",
        "categories" => true
      },
      "excluded_paths" => [
        "vendor/**",
        "node_modules/**"
      ]
    }.freeze

    attr_reader :version, :workers, :priorities, :guardrails, :labels, :excluded_paths, :categories,
                :pr_assignees, :pr_reviewers

    def initialize(config_hash)
      @version = config_hash.fetch("version", 1)

      if @version >= 2
        init_v2(config_hash)
      else
        init_v1(config_hash)
      end
    end

    def self.load(path)
      config_hash = if File.exist?(path)
        YAML.safe_load(File.read(path)) || {}
      else
        {}
      end

      new(config_hash)
    end

    def max_concurrent
      @workers.max_concurrent
    end

    def enabled_priorities
      @priorities.select(&:enabled?)
    end

    def priority_for(category)
      @priorities.find { |p| p.category == category }
    end

    def enabled_categories
      if @version >= 2
        @categories
      else
        enabled_priorities.map(&:category)
      end
    end

    private

    def init_v1(config_hash)
      merged = deep_merge(DEFAULT_CONFIG, config_hash)

      @workers = Workers.new(merged["workers"])
      @priorities = merged["priorities"].map { |p| Priority.new(p) }
      @guardrails = Guardrails.new(merged["guardrails"])
      @labels = Labels.new(merged["labels"])
      @excluded_paths = merged["excluded_paths"]
      @categories = enabled_priorities.map(&:category)
      @pr_assignees = merged.fetch("pr_assignees", [])
      @pr_reviewers = merged.fetch("pr_reviewers", [])
    end

    def init_v2(config_hash)
      @categories = config_hash.fetch("categories", DEFAULT_CATEGORIES)
      @workers = Workers.new("max_concurrent" => config_hash.fetch("max_concurrent", 5))
      @excluded_paths = config_hash.fetch("excluded_paths", ["vendor/**", "node_modules/**"])
      @pr_assignees = config_hash.fetch("pr_assignees", [])
      @pr_reviewers = config_hash.fetch("pr_reviewers", [])

      # Provide v1-compatible accessors with sensible defaults
      @priorities = @categories.map do |cat|
        Priority.new("category" => cat, "max_prs" => 3, "enabled" => true)
      end
      @guardrails = Guardrails.new(
        "max_iterations_per_pr" => 5,
        "max_files_per_pr" => 10,
        "require_tests" => true
      )
      @labels = Labels.new("base" => "claude-gardener", "categories" => true)
    end

    def deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end

    class Workers
      attr_reader :max_concurrent

      def initialize(hash)
        @max_concurrent = hash["max_concurrent"] || 3
      end
    end

    class Priority
      attr_reader :category, :max_prs, :tasks

      def initialize(hash)
        @category = hash["category"]
        @max_prs = hash["max_prs"] || 3
        @enabled = hash.fetch("enabled", true)
        @tasks = hash["tasks"] || []
      end

      def enabled?
        @enabled
      end
    end

    class Guardrails
      attr_reader :max_iterations_per_pr, :max_files_per_pr

      def initialize(hash)
        @max_iterations_per_pr = hash["max_iterations_per_pr"] || 5
        @max_files_per_pr = hash["max_files_per_pr"] || 10
        @require_tests = hash.fetch("require_tests", true)
      end

      def require_tests?
        @require_tests
      end
    end

    class Labels
      attr_reader :base

      def initialize(hash)
        @base = hash["base"] || "claude-gardener"
        @categories = hash.fetch("categories", true)
      end

      def include_categories?
        @categories
      end

      def for_category(category)
        return [base] unless include_categories?

        [base, "#{base}:#{category}"]
      end
    end
  end
end
