# frozen_string_literal: true

require "fileutils"

module Garden
  # Fixes one finding in its own worktree and commits the result.
  class Fixer
    TOOLS = %w[Read Grep Glob Edit Write Bash].freeze
    GIT_COMMANDS = ["git status", "git diff", "git log", "git show"].freeze
    PROMPT_FILE = File.expand_path("prompts/fix_security.md", __dir__)
    # Keep logs and notes a readable size.
    MAX_OUTPUT = 20_000

    SCHEMA = {
      type: "object",
      properties: {
        outcome: { type: "string", enum: %w[fixed not_an_issue failed] },
        summary: { type: "string" },
        commit_message: { type: "string" }
      },
      required: %w[outcome summary commit_message]
    }.freeze

    # What to record on the finding afterwards.
    Outcome = Data.define(:status, :note, :log)
    TestRun = Data.define(:passed, :output)

    def self.branch_name(finding)
      slug = finding.title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")[0, 40].chomp("-")
      "garden/security/#{finding.id}-#{slug}"
    end

    def initialize(project, repo: Repo.new(project.path), claude: Claude.new, shell: Shell,
                   guidance: Guidance.new, logs_dir: Paths.logs_dir)
      @project = project
      @repo = repo
      @claude = claude
      @shell = shell
      @guidance = guidance
      @logs_dir = logs_dir
    end

    # Fixes finding (which already has its branch and worktree set) starting
    # from ref. Returns an Outcome. Raises Error if a step can't run.
    def call(finding, ref)
      dir = finding.worktree
      @repo.add_worktree(dir, finding.branch, ref)
      prepare(dir)

      response = ask(prompt(finding), dir)
      return gave_up(response.data) unless response.data["outcome"] == "fixed"

      tests = run_tests(dir)
      unless tests.passed
        response = ask(retry_prompt(tests.output), dir, resume: response.session_id)
        return gave_up(response.data) unless response.data["outcome"] == "fixed"

        tests = run_tests(dir)
        unless tests.passed
          return Outcome.new(status: "failed", note: "Tests still fail after one retry. " \
                                                     "Claude's summary: #{response.data['summary']}",
                             log: save_log(finding, tests.output))
        end
      end

      unless @repo.changes?(dir, exclude: @project.worktree_files)
        return Outcome.new(status: "failed", note: "Claude said it fixed this but changed nothing. " \
                                                   "Claude's summary: #{response.data['summary']}",
                           log: nil)
      end

      @repo.commit_all(dir, response.data["commit_message"], exclude: @project.worktree_files)
      Outcome.new(status: "pending_review", note: response.data["summary"], log: nil)
    end

    def prompt(finding)
      [File.read(PROMPT_FILE), commit_section, test_section, @guidance.section, issue_section(finding)]
        .compact.join("\n")
    end

    def allowed_tools
      (test_commands + GIT_COMMANDS).flat_map { |c| ["Bash(#{c})", "Bash(#{c} *)"] }
    end

    private

    def test_commands = TestCommands.for(@project)

    # Links ignored files from the main checkout and runs setup commands.
    def prepare(dir)
      @project.worktree_files.each do |file|
        source = File.join(@project.path, file)
        target = File.join(dir, file)
        next unless File.exist?(source) && !File.exist?(target)

        FileUtils.mkdir_p(File.dirname(target))
        File.symlink(source, target)
      end

      @project.setup_commands.each do |command|
        result = @shell.run("sh", "-c", command, chdir: dir, timeout: @project.fix_timeout)
        raise Error, "Setup command `#{command}` failed:\n#{tail(result.out + result.err)}" unless result.success?
      end

      # Anything changed now would end up in the fix's commit.
      return unless @repo.changes?(dir, exclude: @project.worktree_files)

      raise Error, "Setup commands changed files in the worktree. Make them leave tracked files alone, " \
                   "or add the files to .gitignore."
    end

    def ask(prompt, dir, resume: nil)
      @claude.run(prompt: prompt, dir: dir, schema: SCHEMA, tools: TOOLS, allowed_tools: allowed_tools,
                  model: @project.model, permission_mode: "acceptEdits", persist: true,
                  resume: resume, timeout: @project.fix_timeout)
    end

    def run_tests(dir)
      outputs = test_commands.map do |command|
        result = @shell.run("sh", "-c", command, chdir: dir, timeout: @project.fix_timeout)
        return TestRun.new(passed: false, output: "$ #{command}\n#{result.out}#{result.err}") unless result.success?

        "$ #{command}\n#{result.out}#{result.err}"
      end
      TestRun.new(passed: true, output: outputs.join("\n"))
    end

    def gave_up(data)
      note = if data["outcome"] == "not_an_issue"
               "Claude thinks this isn't a real issue: #{data['summary']}"
             else
               "Claude couldn't fix this: #{data['summary']}"
             end
      Outcome.new(status: "failed", note: note, log: nil)
    end

    def save_log(finding, output)
      FileUtils.mkdir_p(@logs_dir)
      path = File.join(@logs_dir, "#{finding.id}.log")
      File.write(path, output)
      path
    end

    def retry_prompt(output)
      <<~TEXT
        Garden ran the tests after your fix and they failed. Here's the output:

        ```
        #{tail(output)}
        ```

        Fix the problem so the tests pass, then report again in the same format.
        If the failure has nothing to do with your change, report `failed` and say so.
      TEXT
    end

    def tail(text)
      text.length > MAX_OUTPUT ? "...\n#{text[-MAX_OUTPUT..]}" : text
    end

    def commit_section
      template = @repo.commit_template
      return "## Commit message\n\nWrite a short subject line, a blank line, then a body explaining the change.\n" unless template

      <<~TEXT
        ## Commit message

        Follow this template. Lines starting with `#` are instructions: follow
        them, but leave them out of the message.

        ```
        #{template.strip}
        ```
      TEXT
    end

    def test_section
      commands = test_commands
      return "## Tests\n\nNo test commands are set up for this project, so you can't run tests.\n" if commands.empty?

      "## Tests\n\nRun the tests with:\n\n#{commands.map { |c| "- `#{c}`" }.join("\n")}\n"
    end

    def issue_section(finding)
      files = finding.files.empty? ? "" : "Files: #{finding.files.join(', ')}\n\n"
      "## The issue\n\n**#{finding.title}** (severity: #{finding.severity})\n\n#{files}#{finding.details}\n"
    end
  end
end
