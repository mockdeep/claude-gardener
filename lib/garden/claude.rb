# frozen_string_literal: true

require "json"

module Garden
  # Runs Claude Code headless (`claude -p`).
  class Claude
    # data matches the schema; session_id can be passed back as resume:.
    Response = Data.define(:data, :session_id)

    def initialize(shell: Shell)
      @shell = shell
    end

    # Runs prompt in dir and returns a Response.
    #
    # tools is the full set Claude can use; allowed_tools are pre-approved
    # patterns (e.g. "Bash(npm audit *)"). permission_mode "dontAsk" allows
    # nothing else; "acceptEdits" also allows edits and basic file commands in
    # dir. Anything that would need a person to approve it is denied.
    #
    # Sessions are only saved when persist is true (needed to resume later).
    def run(prompt:, dir:, schema:, tools:, allowed_tools: [], model: nil,
            permission_mode: "dontAsk", persist: false, resume: nil, timeout: nil)
      cmd = [
        "claude", "-p",
        "--output-format", "json",
        "--permission-mode", permission_mode,
        "--permission-prompts", "none",
        "--tools", tools.join(","),
        "--json-schema", JSON.generate(schema)
      ]
      cmd << "--no-session-persistence" unless persist || resume
      cmd += ["--resume", resume] if resume
      cmd += ["--allowed-tools", allowed_tools.join(",")] if allowed_tools.any?
      cmd += ["--model", model] if model

      result = @shell.run(*cmd, chdir: dir, stdin: prompt, timeout: timeout)
      data = parse(result)
      if !result.success? || data["is_error"]
        raise Error, "Claude failed: #{data['result'] || result.err.strip}"
      end

      output = data["structured_output"] or raise Error, "Claude didn't return structured output"
      Response.new(data: output, session_id: data["session_id"])
    end

    # Like run, but returns only the data.
    def structured(**opts) = run(**opts).data

    private

    def parse(result)
      JSON.parse(result.out)
    rescue JSON::ParserError
      raise Error, "Claude failed: #{result.err.strip.empty? ? result.out.strip : result.err.strip}"
    end
  end
end
