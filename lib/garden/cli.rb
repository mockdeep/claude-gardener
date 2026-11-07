# frozen_string_literal: true

require "optparse"

module Garden
  class CLI
    USAGE = <<~TEXT
      Usage: garden [command] [options]

      With no command, scans every project (if due) and then fixes the most
      severe open findings.

      Commands:
        setup              Link garden's Claude skills into ~/.claude/skills
        add [path]         Register a project (defaults to the current directory)
        scan [project]     Scan for security issues (all projects if none given)
                             --force  rescan even if the last scan is recent
        fix [project]      Fix open findings without scanning
        review             Review fixes one by one with Claude, then approve
                           (open a PR), reject, retry or skip each
        help             Show this message
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
      when "fix" then fix
      when "review" then review
      when "help", "-h", "--help" then help
      when nil then scan_and_fix
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

    # Plain `garden`: scan, then fix. If the scan fails, the saved findings
    # are still fixed.
    def scan_and_fix
      each_project(nil) do |project|
        scanned = scan_project(project, false)
        fix_project(project) && scanned
      end
    end

    def scan
      force = false
      OptionParser.new do |opts|
        opts.banner = "Usage: garden scan [project] [--force]"
        opts.on("--force", "Rescan even if the last scan is recent") { force = true }
      end.parse!(@argv)

      each_project(@argv.first) { |project| scan_project(project, force) }
    end

    def fix
      each_project(@argv.first) { |project| fix_project(project) }
    end

    # Runs the block for the named project, or all of them. The block returns
    # false on failure, which doesn't stop the other projects.
    def each_project(name)
      registry = Registry.new
      projects = name ? [registry.find(name)] : registry.projects
      if projects.empty?
        @out.puts "No projects registered yet. Run `garden add` in a project first."
        return 0
      end

      failed = projects.count do |project|
        @out.puts "== #{project.name}"
        !yield(project)
      end
      failed.zero? ? 0 : 1
    end

    def scan_project(project, force)
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

    def fix_project(project)
      fixed = FixStep.new(project).call do |finding, outcome|
        if outcome.nil?
          @out.puts "Fixing [#{finding.severity}] #{finding.title}"
        elsif outcome.status == "pending_review"
          @out.puts "  Ready for review on #{finding.branch}"
        else
          @out.puts "  Failed: #{outcome.note.lines.first&.strip}"
        end
      end
      @out.puts "Nothing to fix." if fixed.empty?
      true
    rescue Error => e
      @err.puts "#{project.name}: #{e.message}"
      false
    end

    def review
      ReviewQueue.new(terminal: Terminal.new(out: @out)).call
      0
    end

    def help
      @out.puts USAGE
      0
    end

    def unknown(command)
      @err.puts "garden: unknown command '#{command}'\n\n#{USAGE}"
      1
    end
  end
end
