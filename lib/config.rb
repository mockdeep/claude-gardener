# frozen_string_literal: true

require "yaml"

module ClaudeGardener
  class Config
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

    attr_reader :version, :workers, :priorities, :guardrails, :labels, :excluded_paths

    def initialize(config_hash)
      merged = deep_merge(DEFAULT_CONFIG, config_hash)

      @version = merged["version"]
      @workers = Workers.new(merged["workers"])
      @priorities = merged["priorities"].map { |p| Priority.new(p) }
      @guardrails = Guardrails.new(merged["guardrails"])
      @labels = Labels.new(merged["labels"])
      @excluded_paths = merged["excluded_paths"]
    end

    def self.load(path)
      config_hash = if File.exist?(path)
        YAML.safe_load(File.read(path)) || {}
      else
        {}
      end

      new(config_hash)
    end

    def enabled_priorities
      @priorities.select(&:enabled?)
    end

    def priority_for(category)
      @priorities.find { |p| p.category == category }
    end

    private

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
