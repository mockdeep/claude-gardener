# frozen_string_literal: true

require "fileutils"

module Garden
  # Everything the garden-review skill needs to know about one finding,
  # written to reviews/<id>/context.md. The skill writes summary.md beside it.
  class ReviewContext
    GUIDANCE_BRANCH = "garden/guidance"
    LOG_LINES = 80

    def self.guidance_worktree(project)
      File.join(Paths.worktrees_dir, project.name, "guidance")
    end

    def initialize(project, finding, default_ref:, reviews_dir: Paths.reviews_dir,
                   guidance_dir: Paths.guidance_dir, guidance_worktree: self.class.guidance_worktree(project))
      @project = project
      @finding = finding
      @default_ref = default_ref
      @dir = File.join(reviews_dir, finding.id)
      @guidance_dir = guidance_dir
      @guidance_worktree = guidance_worktree
    end

    attr_reader :dir, :guidance_worktree

    def context_path = File.join(dir, "context.md")
    def summary_path = File.join(dir, "summary.md")

    # Folders the review session needs access to besides the fix worktree.
    def extra_dirs = [@guidance_dir, @guidance_worktree, dir]

    # Writes the context file (replacing any old summary) and returns its path.
    def write
      FileUtils.mkdir_p(dir)
      FileUtils.mkdir_p(@guidance_dir)
      FileUtils.rm_f(summary_path)
      File.write(context_path, render)
      context_path
    end

    def render
      [header, issue, note, test_log, where_things_go].compact.join("\n")
    end

    private

    def header
      f = @finding
      <<~TEXT
        # Garden review: #{f.title}

        - Project: #{@project.name} (#{@project.path})
        - Finding id: #{f.id}
        - Status: #{f.status}
        - Severity: #{f.severity}
        - Branch: #{f.branch}
        - Compare against: #{@default_ref} (`git diff #{@default_ref}...HEAD`)
        - Files: #{f.files.empty? ? 'not listed' : f.files.join(', ')}
      TEXT
    end

    def issue
      "## The issue\n\n#{@finding.details || 'No details given.'}\n"
    end

    def note
      return unless @finding.note

      "## Note from the fix\n\n#{@finding.note}\n"
    end

    def test_log
      return unless @finding.log && File.exist?(@finding.log)

      lines = File.readlines(@finding.log)
      cut = lines.size > LOG_LINES ? "(last #{LOG_LINES} of #{lines.size} lines)\n\n" : ""
      "## Test log\n\n#{cut}```\n#{lines.last(LOG_LINES).join.rstrip}\n```\n"
    end

    def where_things_go
      commands = TestCommands.for(@project)
      tests = commands.empty? ? "none set up" : commands.map { |c| "`#{c}`" }.join(", ")
      topics = Dir[File.join(@guidance_dir, "*.md")].map { |f| File.basename(f) }
      <<~TEXT
        ## Where things go

        - Test commands: #{tests}
        - Summary file: `#{summary_path}`
        - General guidance folder: `#{@guidance_dir}` (topic files: #{topics.empty? ? 'none yet' : topics.join(', ')})
        - Guidance worktree (repo-specific lessons): `#{@guidance_worktree}`, on branch `#{GUIDANCE_BRANCH}`
        - Repo-specific guidance file: `#{repo_guidance_file}`
      TEXT
    end

    # AGENTS.md if the repo has one, otherwise CLAUDE.md.
    def repo_guidance_file
      base = File.directory?(@guidance_worktree) ? @guidance_worktree : @project.path
      File.exist?(File.join(base, "AGENTS.md")) ? "AGENTS.md" : "CLAUDE.md"
    end
  end
end
