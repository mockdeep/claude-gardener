# frozen_string_literal: true

require "optparse"

module Garden
  class CLI
    USAGE = <<~TEXT
      Usage: garden <command> [options]

      Commands:
        setup              Link garden's Claude skills into ~/.claude/skills
        add [path]         Register a project (defaults to the current directory)
        scan [project]     Scan for security issues (all projects if none given)
                             --force  rescan even if the last scan is recent
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
      when "scan" then scan
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

    def scan
      force = false
      OptionParser.new do |opts|
        opts.banner = "Usage: garden scan [project] [--force]"
        opts.on("--force", "Rescan even if the last scan is recent") { force = true }
      end.parse!(@argv)

      registry = Registry.new
      projects = @argv.first ? [registry.find(@argv.first)] : registry.projects
      if projects.empty?
        @out.puts "No projects registered yet. Run `garden add` in a project first."
        return 0
      end

      failed = projects.count { |project| !scan_project(project, force) }
      failed.zero? ? 0 : 1
    end

    # Returns false if the scan failed. A failure doesn't stop other projects.
    def scan_project(project, force)
      @out.puts "== #{project.name}"
      status = ScanStep.new(project).call(force: force)
      state = StateStore.new(project.name).read
      if status == :fresh
        @out.puts "Using findings from #{state.scanned_at.localtime.strftime('%Y-%m-%d')} " \
                  "(--force to rescan)"
      end
      print_findings(state)
      true
    rescue Error => e
      @err.puts "#{project.name}: #{e.message}"
      false
    end

    def print_findings(state)
      queue = state.fix_queue
      @out.puts "No open findings." if queue.empty?
      queue.each do |f|
        files = f.files.empty? ? "" : " (#{f.files.join(', ')})"
        @out.puts "  [#{f.severity}] #{f.title}#{files}"
      end
      in_progress = state.in_progress.size
      @out.puts "  ...plus #{in_progress} already in progress" if in_progress.positive?
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
