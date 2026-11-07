# frozen_string_literal: true

module Garden
  # Talks to the person running garden: runs interactive programs (Claude,
  # the commit message editor) and asks questions.
  class Terminal
    def initialize(input: $stdin, out: $stdout)
      @input = input
      @out = out
    end

    # Runs an interactive program in the foreground. Returns true if it
    # exited cleanly.
    #
    # Ctrl-C reaches the program as usual, but garden itself ignores it while
    # the program runs, so pressing it inside Claude doesn't end the review
    # queue. (A no-op handler rather than "IGNORE", because ignored signals
    # carry over to the program.)
    def run(*cmd, chdir: nil)
      previous = trap("INT") {}
      pid = Process.spawn(*cmd, **(chdir ? { chdir: chdir } : {}))
      Process.wait(pid)
      $?.success?
    ensure
      trap("INT", previous || "DEFAULT")
    end

    def run!(*cmd, chdir: nil)
      run(*cmd, chdir: chdir) or raise Error, "`#{cmd.first(4).join(' ')}` didn't finish successfully"
    end

    def say(text) = @out.puts(text)

    # Asks the user to pick one of choices (a hash of answer => key letter).
    # Enter picks default; end of input picks "skip" if offered, else default.
    def choose(question, choices, default:)
      labels = choices.map { |name, key| name == default ? "#{name} (#{key}, default)" : "#{name} (#{key})" }
      loop do
        @out.print "#{question} #{labels.join(' / ')}: "
        line = @input.gets
        return choices.key?("skip") ? "skip" : default if line.nil?

        answer = line.strip.downcase
        return default if answer.empty?

        match = choices.find { |name, key| answer == name || answer == key }
        return match.first if match

        @out.puts "Please answer with one of: #{choices.keys.join(', ')}"
      end
    end

    def yes?(question, default: true)
      @out.print "#{question} #{default ? '(Y/n)' : '(y/N)'} "
      answer = @input.gets&.strip&.downcase
      return false if answer.nil?
      return default if answer.empty?

      answer.start_with?("y")
    end
  end
end
