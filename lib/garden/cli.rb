# frozen_string_literal: true

require "optparse"

module Garden
  class CLI
    USAGE = <<~TEXT
      Usage: garden <command> [options]

      Commands:
        setup              Link garden's Claude skills into ~/.claude/skills
        add [path]         Register a project (defaults to the current directory)
        help               Show this message
    TEXT

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
    end

    # Returns the exit status.
    def run
      command = @argv.shift
      case command
      when "setup" then setup
      when "add" then add
      when "help", "-h", "--help" then help
      when nil then not_built_yet
      else unknown(command)
      end
    rescue Error, OptionParser::ParseError => e
      @err.puts "garden: #{e.message}"
      1
    end

    private

    def setup
      Setup.new.run.each do |skill, status|
        @out.puts(status == :linked ? "Linked #{skill}" : "#{skill} already linked")
      end
      0
    end

    def add
      name = nil
      OptionParser.new do |opts|
        opts.banner = "Usage: garden add [path] [--name NAME]"
        opts.on("--name NAME", "Name to register the project under") { |v| name = v }
      end.parse!(@argv)

      status, project = Registry.new.add(@argv.first || Dir.pwd, name: name)
      if status == :added
        @out.puts "Added #{project.name} (#{project.path})"
      else
        @out.puts "#{project.name} is already registered (#{project.path})"
      end
      0
    end

    def help
      @out.puts USAGE
      0
    end

    def not_built_yet
      @err.puts "garden: scanning isn't built yet.\n\n#{USAGE}"
      1
    end

    def unknown(command)
      @err.puts "garden: unknown command '#{command}'\n\n#{USAGE}"
      1
    end
  end
end
