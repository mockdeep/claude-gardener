# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::TaskSelector do
  let(:config) do
    ClaudeGardener::Config.new(
      "priorities" => [
        { "category" => "test_coverage", "max_prs" => 2, "enabled" => true },
        { "category" => "security_fixes", "max_prs" => 1, "enabled" => true },
        { "category" => "linter_fixes", "max_prs" => 3, "enabled" => false }
      ]
    )
  end

  let(:pr_manager) { instance_double(ClaudeGardener::PrManager) }
  let(:lock_checker) { instance_double(ClaudeGardener::LockChecker, locked_files: Set.new) }

  subject(:selector) do
    described_class.new(
      config: config,
      pr_manager: pr_manager,
      lock_checker: lock_checker
    )
  end

  describe "#select_next_task" do
    it "selects first available category with capacity" do
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("test_coverage")
        .and_return([double, double])
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("security_fixes")
        .and_return([])

      task = selector.select_next_task

      expect(task.category).to eq("security_fixes")
    end

    it "returns nil when all categories are at capacity" do
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("test_coverage")
        .and_return([double, double])
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("security_fixes")
        .and_return([double])

      task = selector.select_next_task

      expect(task).to be_nil
    end

    it "skips disabled categories" do
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("test_coverage")
        .and_return([double, double])
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("security_fixes")
        .and_return([double])

      task = selector.select_next_task

      expect(task).to be_nil
    end
  end

  describe "#select_task_for_category" do
    it "returns a task when category has capacity" do
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("test_coverage")
        .and_return([])

      task = selector.select_task_for_category("test_coverage")

      expect(task).not_to be_nil
      expect(task.category).to eq("test_coverage")
      expect(task.prompt).to include("test coverage")
    end

    it "returns nil when category is at capacity" do
      allow(pr_manager).to receive(:open_prs_for_category)
        .with("test_coverage")
        .and_return([double, double])

      task = selector.select_task_for_category("test_coverage")

      expect(task).to be_nil
    end

    it "returns nil for disabled category" do
      task = selector.select_task_for_category("linter_fixes")

      expect(task).to be_nil
    end

    it "returns nil for unknown category" do
      task = selector.select_task_for_category("unknown")

      expect(task).to be_nil
    end

    it "includes locked files in the task" do
      allow(lock_checker).to receive(:locked_files).and_return(Set.new(["file.rb"]))
      allow(pr_manager).to receive(:open_prs_for_category).and_return([])

      task = selector.select_task_for_category("test_coverage")

      expect(task.locked_files).to include("file.rb")
    end
  end
end
