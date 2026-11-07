# frozen_string_literal: true

module Garden
  # Asks Claude to look for security issues and turns the answer into findings.
  class Scanner
    TOOLS = %w[Read Grep Glob Bash].freeze
    AUDIT_COMMANDS = [
      "bundle audit", "bundle-audit", "npm audit", "yarn audit", "pnpm audit", "pip-audit", "cargo audit"
    ].freeze
    MAX_FINDINGS = 10
    PROMPT_FILE = File.expand_path("prompts/scan_security.md", __dir__)

    SCHEMA = {
      type: "object",
      properties: {
        findings: {
          type: "array",
          maxItems: MAX_FINDINGS,
          items: {
            type: "object",
            properties: {
              title: { type: "string", description: "Short summary, under 70 characters" },
              details: { type: "string", description: "What's wrong, where, and how to fix it" },
              files: { type: "array", items: { type: "string" }, description: "Paths relative to the repo root" },
              severity: { type: "string", enum: Finding::SEVERITIES }
            },
            required: %w[title details files severity]
          }
        }
      },
      required: ["findings"]
    }.freeze

    def initialize(project, claude: Claude.new, guidance_dir: Paths.guidance_dir)
      @project = project
      @claude = claude
      @guidance_dir = guidance_dir
    end

    # Scans the code in dir. state supplies the findings not to report again.
    def scan(dir, state)
      data = @claude.structured(
        prompt: prompt(state), dir: dir, schema: SCHEMA, tools: TOOLS,
        allowed_tools: allowed_tools, model: @project.model
      )
      data.fetch("findings", []).first(MAX_FINDINGS).map do |f|
        Finding.build(title: f.fetch("title"), details: f["details"], files: f["files"] || [],
                      severity: f.fetch("severity"))
      end
    end

    def prompt(state)
      [File.read(PROMPT_FILE), guidance, known(state)].compact.join("\n")
    end

    # Each command allowed bare or with arguments.
    def allowed_tools
      (AUDIT_COMMANDS + @project.audit_commands).uniq.flat_map { |c| ["Bash(#{c})", "Bash(#{c} *)"] }
    end

    private

    def guidance
      files = Dir[File.join(@guidance_dir, "*.md")]
      return if files.empty?

      sections = files.map { |f| "### #{File.basename(f, '.md')}\n\n#{File.read(f).strip}\n" }
      "## Guidance\n\nFollow this guidance from past reviews.\n\n#{sections.join("\n")}"
    end

    def known(state)
      lines = state.in_progress.map { |f| "- (in progress) #{describe(f)}" }
      lines += state.rejections.map { |f| "- (rejected) #{describe(f)}#{" Reason: #{f.reason}" if f.reason}" }
      return if lines.empty?

      <<~TEXT
        ## Already known

        These are already being fixed or were recently turned down. Don't report
        them again, or anything that is really the same issue in other words.

        #{lines.join("\n")}
      TEXT
    end

    def describe(finding)
      files = finding.files.empty? ? "" : " (#{finding.files.join(', ')})"
      "#{finding.title}#{files}."
    end
  end
end
