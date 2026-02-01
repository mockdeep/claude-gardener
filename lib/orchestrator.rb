# frozen_string_literal: true

require_relative "github_client"
require_relative "task_selector"
require_relative "pr_manager"
require_relative "lock_checker"
require_relative "claude_runner"
require_relative "iteration_tracker"

module ClaudeGardener
  class Orchestrator
    def initialize(config:, event_type:, event_data:, category: "auto")
      @config = config
      @event_type = event_type
      @event_data = event_data
      @category = category
      @github = GithubClient.new
      @pr_manager = PrManager.new(github: @github, config: config)
      @lock_checker = LockChecker.new(github: @github, config: config)
      @task_selector = TaskSelector.new(
        config: config,
        pr_manager: @pr_manager,
        lock_checker: @lock_checker
      )
      @claude = ClaudeRunner.new
    end

    def run
      case @event_type
      when "workflow_dispatch"
        handle_workflow_dispatch
      when "pull_request_review"
        handle_pull_request_review
      when "push"
        handle_push
      else
        puts "Unknown event type: #{@event_type}"
        exit 1
      end
    end

    private

    def handle_workflow_dispatch
      puts "Starting new gardening task..."

      if at_worker_capacity?
        puts "At worker capacity (#{@config.workers.max_concurrent} concurrent PRs). Exiting."
        return
      end

      task = if @category == "auto"
        @task_selector.select_next_task
      else
        @task_selector.select_task_for_category(@category)
      end

      unless task
        puts "No tasks available. All categories at max PRs or no work to do."
        return
      end

      puts "Selected task: #{task.category}"
      execute_task(task)
    end

    def handle_pull_request_review
      pr_number = @event_data.dig("pull_request", "number")
      review_state = @event_data.dig("review", "state")

      puts "Handling PR review for ##{pr_number} (#{review_state})"

      return unless gardener_pr?(pr_number)

      case review_state
      when "changes_requested", "commented"
        handle_review_feedback(pr_number)
      when "approved"
        puts "PR approved! Ready to merge."
      end
    end

    def handle_push
      commit_message = @event_data.dig("head_commit", "message") || ""

      unless commit_message.include?("[gardener]")
        puts "Push is not from a gardener PR. Skipping."
        return
      end

      puts "Gardener PR merged. Checking for more work..."
      handle_workflow_dispatch
    end

    def execute_task(task)
      branch_name = generate_branch_name(task.category)

      puts "Creating branch: #{branch_name}"
      @github.create_branch(branch_name)

      puts "Running Claude to make improvements..."
      result = @claude.run(
        prompt: task.prompt,
        branch: branch_name,
        config: @config
      )

      if result.success?
        puts "Claude completed successfully. Creating PR..."
        pr = @pr_manager.create_pr(
          branch: branch_name,
          category: task.category,
          title: result.pr_title,
          body: result.pr_body
        )
        puts "Created PR ##{pr.number}: #{pr.html_url}"
      else
        puts "Claude failed: #{result.error}"
        @github.delete_branch(branch_name)
      end
    end

    def handle_review_feedback(pr_number)
      pr = @github.pull_request(pr_number)
      tracker = IterationTracker.new(pr)

      if tracker.iterations >= @config.guardrails.max_iterations_per_pr
        puts "PR has reached max iterations (#{tracker.iterations}). Adding needs-human label."
        @pr_manager.add_label(pr_number, "needs-human")
        @pr_manager.add_comment(pr_number, <<~MSG)
          This PR has reached the maximum number of iterations (#{@config.guardrails.max_iterations_per_pr}).
          A human needs to review and either provide guidance or take over.
        MSG
        return
      end

      puts "Addressing review feedback (iteration #{tracker.iterations + 1})..."

      review_comments = @github.review_comments(pr_number)
      pr_comments = @github.issue_comments(pr_number)

      result = @claude.address_feedback(
        pr: pr,
        review_comments: review_comments,
        pr_comments: pr_comments,
        config: @config
      )

      if result.success?
        tracker.increment
        @pr_manager.update_metadata(pr_number, tracker)
        puts "Feedback addressed. Pushed updates."
      else
        puts "Failed to address feedback: #{result.error}"
      end
    end

    def gardener_pr?(pr_number)
      pr = @github.pull_request(pr_number)
      pr.labels.any? { |label| label.name == @config.labels.base }
    end

    def at_worker_capacity?
      open_prs = @pr_manager.open_gardener_prs
      open_prs.count >= @config.workers.max_concurrent
    end

    def generate_branch_name(category)
      timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
      "gardener/#{category}/#{timestamp}"
    end
  end
end
