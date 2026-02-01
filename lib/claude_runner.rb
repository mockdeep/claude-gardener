# frozen_string_literal: true

require "open3"
require "json"

module ClaudeGardener
  class ClaudeRunner
    class Result
      attr_reader :pr_title, :pr_body, :error

      def initialize(success:, pr_title: nil, pr_body: nil, error: nil)
        @success = success
        @pr_title = pr_title
        @pr_body = pr_body
        @error = error
      end

      def success?
        @success
      end
    end

    def run(prompt:, branch:, config:)
      full_prompt = build_prompt(prompt, config)

      # Switch to the branch
      system("git", "checkout", branch)

      output, status = Open3.capture2e(
        "claude",
        "--print",
        "--dangerously-skip-permissions",
        full_prompt
      )

      unless status.success?
        return Result.new(success: false, error: "Claude CLI failed: #{output}")
      end

      # Check if any changes were made
      changes_output, = Open3.capture2e("git", "status", "--porcelain")

      if changes_output.strip.empty?
        return Result.new(success: false, error: "No changes were made")
      end

      # Commit and push changes
      system("git", "add", "-A")
      system("git", "commit", "-m", "[gardener] Automated improvements")
      system("git", "push", "-u", "origin", branch)

      # Extract PR title and body from output
      pr_title, pr_body = extract_pr_info(output)

      Result.new(
        success: true,
        pr_title: pr_title || "Automated code improvements",
        pr_body: pr_body || "This PR contains automated improvements made by Claude Gardener."
      )
    end

    def address_feedback(pr:, review_comments:, pr_comments:, config:)
      prompt = build_feedback_prompt(pr, review_comments, pr_comments, config)

      # Checkout the PR branch
      branch = pr.head.ref
      system("git", "fetch", "origin", branch)
      system("git", "checkout", branch)

      output, status = Open3.capture2e(
        "claude",
        "--print",
        "--dangerously-skip-permissions",
        prompt
      )

      unless status.success?
        return Result.new(success: false, error: "Claude CLI failed: #{output}")
      end

      # Check if any changes were made
      changes_output, = Open3.capture2e("git", "status", "--porcelain")

      if changes_output.strip.empty?
        return Result.new(success: false, error: "No changes were made")
      end

      # Commit and push changes
      system("git", "add", "-A")
      system("git", "commit", "-m", "[gardener] Address review feedback")
      system("git", "push")

      Result.new(success: true)
    end

    private

    def build_prompt(base_prompt, config)
      <<~PROMPT
        #{base_prompt}

        ## Guidelines

        - Keep changes focused and minimal
        - Maximum #{config.guardrails.max_files_per_pr} files per PR
        - #{config.guardrails.require_tests? ? "Include or update tests for your changes" : "Tests are optional"}
        - Follow existing code conventions
        - Read CLAUDE.md if present for project-specific guidelines

        ## Excluded Paths

        Do not modify files in these paths:
        #{config.excluded_paths.map { |p| "- #{p}" }.join("\n")}

        ## Output Format

        After making changes, output a summary in this format:

        PR_TITLE: <concise title describing the change>
        PR_BODY: <detailed description of what was changed and why>

        If you discover something worth documenting for future reference,
        update CLAUDE.md or create a skill file in .claude/skills/.
      PROMPT
    end

    def build_feedback_prompt(pr, review_comments, pr_comments, _config)
      feedback_section = format_feedback(review_comments, pr_comments)

      <<~PROMPT
        You are addressing review feedback on PR ##{pr.number}: #{pr.title}

        ## Original PR Description

        #{pr.body}

        ## Review Feedback

        #{feedback_section}

        ## Instructions

        Address the feedback above by making the necessary changes.
        If you disagree with feedback, explain why in a comment.
        If feedback is unclear, make your best judgment and note it.

        After addressing feedback, summarize what you changed.
      PROMPT
    end

    def format_feedback(review_comments, pr_comments)
      sections = []

      if review_comments.any?
        sections << "### Code Review Comments\n\n"
        review_comments.each do |comment|
          sections << "**#{comment.path}:#{comment.line || "general"}** by @#{comment.user.login}:\n"
          sections << "> #{comment.body.gsub("\n", "\n> ")}\n\n"
        end
      end

      if pr_comments.any?
        sections << "### PR Comments\n\n"
        pr_comments.each do |comment|
          next if comment.body.include?("gardener-metadata")

          sections << "**@#{comment.user.login}**:\n"
          sections << "> #{comment.body.gsub("\n", "\n> ")}\n\n"
        end
      end

      sections.empty? ? "No specific feedback provided." : sections.join
    end

    def extract_pr_info(output)
      title_match = output.match(/PR_TITLE:\s*(.+)$/i)
      body_match = output.match(/PR_BODY:\s*(.+?)(?=PR_TITLE:|$)/im)

      title = title_match ? title_match[1].strip : nil
      body = body_match ? body_match[1].strip : nil

      [title, body]
    end
  end
end
