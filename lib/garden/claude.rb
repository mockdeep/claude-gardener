# frozen_string_literal: true

require "json"

module Garden
  # Runs Claude Code headless (`claude -p`).
  class Claude
    def initialize(shell: Shell)
      @shell = shell
    end

    # Runs prompt in dir and returns Claude's answer as data matching schema.
    # tools is the full set Claude can use; allowed_tools are pre-approved
    # patterns (e.g. "Bash(npm audit *)"). Anything else is denied.
    def structured(prompt:, dir:, schema:, tools:, allowed_tools: [], model: nil)
      cmd = [
        "claude", "-p",
        "--output-format", "json",
        "--no-session-persistence",
        "--permission-mode", "dontAsk",
        "--tools", tools.join(","),
        "--json-schema", JSON.generate(schema)
      ]
      cmd += ["--allowed-tools", allowed_tools.join(",")] if allowed_tools.any?
      cmd += ["--model", model] if model

      result = @shell.run(*cmd, chdir: dir, stdin: prompt)
      data = parse(result)
      if !result.success? || data["is_error"]
        raise Error, "Claude failed: #{data['result'] || result.err.strip}"
      end

      data["structured_output"] or raise Error, "Claude didn't return structured output"
    end

    private

    def parse(result)
      JSON.parse(result.out)
    rescue JSON::ParserError
      raise Error, "Claude failed: #{result.err.strip.empty? ? result.out.strip : result.err.strip}"
    end
  end
end
