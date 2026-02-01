# frozen_string_literal: true

module ClaudeGardener
  class TaskSelector
    def initialize(config:, pr_manager:, lock_checker:)
      @config = config
      @pr_manager = pr_manager
      @lock_checker = lock_checker
    end

    def select_next_task
      @config.enabled_priorities.each do |priority|
        task = select_task_for_category(priority.category)
        return task if task
      end

      nil
    end

    def select_task_for_category(category)
      priority = @config.priority_for(category)
      return nil unless priority&.enabled?

      open_prs = @pr_manager.open_prs_for_category(category)
      return nil if open_prs.count >= priority.max_prs

      Task.new(
        category: category,
        prompt: load_prompt(category, priority.tasks),
        locked_files: @lock_checker.locked_files
      )
    end

    private

    def load_prompt(category, custom_tasks = [])
      prompt_file = File.join(__dir__, "prompts", "#{category}.md")

      base_prompt = if File.exist?(prompt_file)
        File.read(prompt_file)
      else
        default_prompt_for(category)
      end

      if custom_tasks.any?
        base_prompt + "\n\n## Custom Tasks\n\n" + custom_tasks.map { |t| "- #{t}" }.join("\n")
      else
        base_prompt
      end
    end

    def default_prompt_for(category)
      <<~PROMPT
        You are improving the codebase in the area of: #{category}

        Look for opportunities to make small, focused improvements.
        Keep your changes to a single logical unit of work.
        Follow existing patterns and conventions in the codebase.
        Read CLAUDE.md if present for project-specific guidelines.
      PROMPT
    end
  end

  class Task
    attr_reader :category, :prompt, :locked_files

    def initialize(category:, prompt:, locked_files:)
      @category = category
      @prompt = prompt
      @locked_files = locked_files
    end
  end
end
