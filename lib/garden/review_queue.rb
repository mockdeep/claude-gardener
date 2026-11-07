# frozen_string_literal: true

module Garden
  # `garden review`: goes through every finding waiting for review, runs an
  # interactive review session for each, and carries out the decision.
  class ReviewQueue
    CHOICES = { "approve" => "a", "reject" => "r", "retry" => "t", "skip" => "s" }.freeze
    GUIDANCE_BRANCH = ReviewContext::GUIDANCE_BRANCH

    def initialize(registry: Registry.new, terminal: Terminal.new, github: GitHub.new,
                   repo_for: ->(project) { Repo.new(project.path) },
                   store_for: ->(project) { StateStore.new(project.name) })
      @registry = registry
      @terminal = terminal
      @github = github
      @repo_for = repo_for
      @store_for = store_for
    end

    # Every reviewable finding as [project, finding], most severe first.
    def queue
      items = @registry.projects.flat_map do |project|
        @store_for.call(project).read.review_queue.map { |finding| [project, finding] }
      end
      items.each_with_index
           .sort_by { |(_, f), i| [Finding::SEVERITIES.index(f.severity), i] }
           .map(&:first)
    end

    def call
      items = queue
      if items.empty?
        @terminal.say "Nothing to review."
        return
      end

      reviewed = []
      items.each_with_index do |(project, finding), i|
        @terminal.say "\n== #{project.name}: [#{finding.severity}] #{finding.title} (#{i + 1} of #{items.size})"
        review(project, finding)
        reviewed << project unless reviewed.include?(project)
        break if i < items.size - 1 && !@terminal.yes?("Next?")
      end
      reviewed.each { |project| publish_guidance(project) }
    end

    private

    def review(project, finding)
      repo = @repo_for.call(project)
      repo.fetch
      ref = repo.default_ref
      context = ReviewContext.new(project, finding, default_ref: ref)
      prepare_guidance(repo, context.guidance_worktree, ref)
      # Recreate the fix worktree if it went missing (e.g. a failed fix).
      repo.ensure_worktree(finding.worktree, finding.branch, ref)
      path = context.write

      # The prompt goes first: --add-dir takes a list and would swallow it.
      @terminal.run("claude", "/garden-review #{path}", "--add-dir", *context.extra_dirs, chdir: finding.worktree)

      decide(project, finding, repo, ref, ReviewSummary.read(context.summary_path))
    rescue Error => e
      @terminal.say "Couldn't finish this one: #{e.message}\nIt's still in the queue."
    end

    def decide(project, finding, repo, ref, summary)
      choices = CHOICES.dup
      choices.delete("approve") unless repo.commits_since?(finding.worktree, ref)
      if summary.present?
        @terminal.say "Suggested: #{summary.decision || 'none'}#{" (#{summary.reason})" if summary.reason}"
      else
        @terminal.say "No review summary was written."
      end
      default = choices.key?(summary.decision) ? summary.decision : "skip"

      case @terminal.choose("Decision?", choices, default: default)
      when "approve" then approve(project, finding, repo, ref)
      when "reject" then reject(project, finding, repo, summary)
      when "retry" then retry_later(project, finding, repo)
      else @terminal.say "Skipped."
      end
    end

    def approve(project, finding, repo, ref)
      dir = finding.worktree
      repo.rebase(dir, ref)
      @terminal.run!("git", "-C", dir, "commit", "--amend")
      repo.push(dir, finding.branch)
      url = @github.open_pr(dir, finding.branch) ||
            @github.create_pr(dir, branch: finding.branch, base: base_branch(ref))
      @store_for.call(project).update { |s| s.update(finding.id, status: "approved", pr_url: url) }
      repo.remove_worktree(dir)
      @terminal.say "Opened #{url}"
    end

    def reject(project, finding, repo, summary)
      clean_up(finding, repo)
      @store_for.call(project).update { |s| s.reject(finding.id, reason: summary.reason) }
      @terminal.say "Rejected."
    end

    def retry_later(project, finding, repo)
      clean_up(finding, repo)
      @store_for.call(project).update do |s|
        s.update(finding.id, status: "open", branch: nil, worktree: nil, note: nil, log: nil)
      end
      @terminal.say "It'll be fixed again on the next run."
    end

    def clean_up(finding, repo)
      repo.remove_worktree(finding.worktree)
      repo.delete_branch(finding.branch)
    end

    # Starts the guidance branch fresh once its last PR is done with, unless
    # it has unsaved or unpushed work.
    def prepare_guidance(repo, dir, ref)
      if File.directory?(dir) && !repo.changes?(dir) && !repo.unpushed_commits?(dir) &&
         @github.open_pr(dir, GUIDANCE_BRANCH).nil?
        repo.reset_to(dir, ref)
      end
      repo.ensure_worktree(dir, GUIDANCE_BRANCH, ref)
    end

    def publish_guidance(project)
      repo = @repo_for.call(project)
      dir = ReviewContext.guidance_worktree(project)
      return unless File.directory?(dir) && repo.changes?(dir)

      @terminal.say "\n== #{project.name}: saving guidance changes"
      repo.stage_all(dir)
      @terminal.run!("git", "-C", dir, "commit")
      repo.push(dir, GUIDANCE_BRANCH)
      url = @github.open_pr(dir, GUIDANCE_BRANCH) ||
            @github.create_pr(dir, branch: GUIDANCE_BRANCH, base: base_branch(repo.default_ref),
                                   fill: "--fill-first")
      @terminal.say "Guidance PR: #{url}"
    rescue Error => e
      @terminal.say "Couldn't save guidance for #{project.name}: #{e.message}\n" \
                    "The changes are still in #{dir}."
    end

    # "origin/main" -> "main"
    def base_branch(ref) = ref.delete_prefix("origin/")
  end
end
