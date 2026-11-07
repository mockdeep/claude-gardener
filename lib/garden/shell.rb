# frozen_string_literal: true

require "open3"

module Garden
  # Runs outside commands. Kept in one place so tests can swap it out.
  module Shell
    Result = Data.define(:out, :err, :status) do
      def success? = status.success?
    end

    module_function

    def run(*cmd, chdir: nil, stdin: nil)
      opts = {}
      opts[:chdir] = chdir if chdir
      opts[:stdin_data] = stdin if stdin
      out, err, status = Open3.capture3(*cmd, **opts)
      Result.new(out: out, err: err, status: status)
    end

    # Like run, but raises if the command fails.
    def run!(*cmd, **opts)
      result = run(*cmd, **opts)
      return result if result.success?

      message = result.err.strip.empty? ? result.out.strip : result.err.strip
      raise Error, "`#{cmd.first(3).join(' ')}` failed: #{message}"
    end
  end
end
