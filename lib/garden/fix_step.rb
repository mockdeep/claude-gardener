# frozen_string_literal: true

module Garden
  # The second part of a garden run for one project: fix the most severe open
  # findings, up to the project's fix_limit.
  class FixStep
    def initialize(project, store: StateStore.new(project.name), repo: Repo.new(project.path),
                   fixer: Fixer.new(project, repo: repo), worktrees_dir: Paths.worktrees_dir)
      @project = project
      @store = store
      @repo = repo
      @fixer = fixer
      @worktrees_dir = worktrees_dir
    end

    # Yields (finding, nil) as each fix starts and (finding, outcome) when it
    # ends. Returns the updated findings.
    def call
      recover
      @repo.fetch
      ref = @repo.default_ref
      @store.read.fix_queue.first(@project.fix_limit).map do |finding|
        branch = Fixer.branch_name(finding)
        started = @store.update do |state|
          state.update(finding.id, status: "fixing", branch: branch,
                                   worktree: File.join(@worktrees_dir, @project.name, branch.tr("/", "-")))
        end
        yield started, nil if block_given?

        outcome = fix(started, ref)
        done = @store.update do |state|
          state.update(finding.id, status: outcome.status, note: outcome.note, log: outcome.log)
        end
        yield done, outcome if block_given?
        done
      end
    end

    private

    def fix(finding, ref)
      @fixer.call(finding, ref)
    rescue Error => e
      Fixer::Outcome.new(status: "failed", note: e.message, log: nil)
    end

    # A finding still marked fixing means an earlier run stopped partway.
    def recover
      @store.update do |state|
        state.findings.select { |f| f.status == "fixing" }.each do |f|
          state.update(f.id, status: "failed", note: "Garden stopped partway through fixing this.")
        end
      end
    end
  end
end
