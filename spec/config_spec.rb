# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::Config do
  describe ".load" do
    it "loads config from a YAML file" do
      config_content = <<~YAML
        version: 1
        workers:
          max_concurrent: 5
        priorities:
          - category: test_coverage
            max_prs: 2
            enabled: true
      YAML

      allow(File).to receive(:exist?).with("test-config.yml").and_return(true)
      allow(File).to receive(:read).with("test-config.yml").and_return(config_content)

      config = described_class.load("test-config.yml")

      expect(config.workers.max_concurrent).to eq(5)
    end

    it "uses defaults when file doesn't exist" do
      allow(File).to receive(:exist?).with("missing.yml").and_return(false)

      config = described_class.load("missing.yml")

      expect(config.workers.max_concurrent).to eq(3)
    end
  end

  describe "#enabled_priorities" do
    it "returns only enabled priorities" do
      config = described_class.new(
        "priorities" => [
          { "category" => "test_coverage", "enabled" => true },
          { "category" => "security_fixes", "enabled" => false },
          { "category" => "linter_fixes", "enabled" => true }
        ]
      )

      enabled = config.enabled_priorities

      expect(enabled.map(&:category)).to eq(%w[test_coverage linter_fixes])
    end
  end

  describe "#priority_for" do
    it "finds a priority by category" do
      config = described_class.new(
        "priorities" => [
          { "category" => "test_coverage", "max_prs" => 5 }
        ]
      )

      priority = config.priority_for("test_coverage")

      expect(priority.max_prs).to eq(5)
    end

    it "returns nil for unknown category" do
      config = described_class.new({})

      expect(config.priority_for("unknown")).to be_nil
    end
  end

  describe "v2 schema" do
    it "parses v2 config" do
      config = described_class.new(
        "version" => 2,
        "max_concurrent" => 7,
        "categories" => %w[test_coverage security_fixes]
      )

      expect(config.version).to eq(2)
      expect(config.max_concurrent).to eq(7)
      expect(config.categories).to eq(%w[test_coverage security_fixes])
    end

    it "provides v1-compatible accessors" do
      config = described_class.new(
        "version" => 2,
        "categories" => %w[test_coverage]
      )

      expect(config.workers.max_concurrent).to eq(5)
      expect(config.priorities.length).to eq(1)
      expect(config.priorities.first.category).to eq("test_coverage")
      expect(config.guardrails.max_files_per_pr).to eq(10)
      expect(config.labels.base).to eq("claude-gardener")
    end

    it "uses default categories when none specified" do
      config = described_class.new("version" => 2)

      expect(config.categories).to eq(%w[test_coverage security_fixes linter_fixes code_improvements])
    end

    it "uses default excluded_paths" do
      config = described_class.new("version" => 2)

      expect(config.excluded_paths).to include("vendor/**")
    end
  end

  describe "#enabled_categories" do
    it "returns enabled category names for v1" do
      config = described_class.new(
        "priorities" => [
          { "category" => "test_coverage", "enabled" => true },
          { "category" => "security_fixes", "enabled" => false }
        ]
      )

      expect(config.enabled_categories).to eq(%w[test_coverage])
    end

    it "returns all categories for v2" do
      config = described_class.new(
        "version" => 2,
        "categories" => %w[test_coverage security_fixes]
      )

      expect(config.enabled_categories).to eq(%w[test_coverage security_fixes])
    end
  end

  describe "#max_concurrent" do
    it "delegates to workers" do
      config = described_class.new({})

      expect(config.max_concurrent).to eq(3)
    end
  end

  describe ClaudeGardener::Config::Labels do
    describe "#for_category" do
      it "returns base label and category label when categories enabled" do
        labels = described_class.new("base" => "gardener", "categories" => true)

        expect(labels.for_category("test_coverage")).to eq(%w[gardener gardener:test_coverage])
      end

      it "returns only base label when categories disabled" do
        labels = described_class.new("base" => "gardener", "categories" => false)

        expect(labels.for_category("test_coverage")).to eq(%w[gardener])
      end
    end
  end
end
