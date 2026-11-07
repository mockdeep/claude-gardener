# frozen_string_literal: true

require "open3"

module Garden
  # Runs outside commands. Kept in one place so tests can swap it out.
  module Shell
    Result = Data.define(:out, :err, :status) do
      def success? = status.success?
    end

    module_function

    # timeout is in seconds. When it runs out, the command and anything it
    # started are stopped, and Error is raised.
    #
    # Commands run in their own process group so all of it can be stopped.
    # That also means Ctrl-C doesn't reach them, so they're stopped here if
    # garden is interrupted.
    def run(*cmd, chdir: nil, stdin: nil, timeout: nil)
      opts = { pgroup: true }
      opts[:chdir] = chdir if chdir
      Open3.popen3(*cmd, **opts) do |input, out, err, wait|
        readers = [out, err].map { |io| Thread.new { io.read } }
        input.write(stdin) if stdin
        input.close
        stop(wait, cmd, timeout) unless wait.join(timeout)
        Result.new(out: readers[0].value, err: readers[1].value, status: wait.value)
      ensure
        signal(-wait.pid, "TERM") if wait.alive?
      end
    end

    # Like run, but raises if the command fails.
    def run!(*cmd, **opts)
      result = run(*cmd, **opts)
      return result if result.success?

      message = result.err.strip.empty? ? result.out.strip : result.err.strip
      raise Error, "`#{cmd.first(3).join(' ')}` failed: #{message}"
    end

    def stop(wait, cmd, timeout)
      group = -wait.pid
      signal(group, "TERM")
      signal(group, "KILL") unless wait.join(5)
      raise Error, "`#{cmd.first(3).join(' ')}` didn't finish within #{timeout} seconds"
    end

    def signal(group, name)
      Process.kill(name, group)
    rescue Errno::ESRCH
      nil
    end
  end
end
