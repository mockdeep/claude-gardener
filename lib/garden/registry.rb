# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

module Garden
  # The list of projects garden works on, stored in projects.yml:
  #
  #   defaults:               # optional, applies to every project
  #     model: opus
  #   projects:
  #     - name: my-app
  #       path: /home/me/code/my-app
  #       fix_limit: 3        # optional, defaults to DEFAULT_FIX_LIMIT
  #       model: sonnet       # optional, defaults to Claude's own default
  #       audit_commands: [composer audit]  # optional, added to the built-in list
  class Registry
    DEFAULT_FIX_LIMIT = 2
    SETTINGS = %w[fix_limit model audit_commands].freeze

    Project = Data.define(:name, :path, :fix_limit, :model, :audit_commands)

    def initialize(file = Paths.projects_file)
      @file = file
    end

    def projects
      defaults = data.fetch("defaults", nil) || {}
      entries.map do |entry|
        settings = defaults.slice(*SETTINGS).merge(entry.slice(*SETTINGS))
        Project.new(
          name: entry.fetch("name"),
          path: entry.fetch("path"),
          fix_limit: settings.fetch("fix_limit", DEFAULT_FIX_LIMIT),
          model: settings["model"],
          audit_commands: Array(settings["audit_commands"])
        )
      end
    end

    def find(name)
      projects.find { |p| p.name == name } or raise Error, "No project named '#{name}'. See #{@file}."
    end

    # Registers the git repo at (or containing) path. Returns [status, project]
    # where status is :added or :exists.
    def add(path, name: nil)
      root = git_root(path)
      existing = projects.find { |p| p.path == root }
      return [:exists, existing] if existing

      name ||= File.basename(root)
      # The name is used in file and folder names, so keep it simple.
      unless name.match?(/\A[\w.-]+\z/) && !name.start_with?(".")
        raise Error, "Project name '#{name}' can only use letters, numbers, '.', '_' and '-'. " \
                     "Pick another with --name."
      end
      if projects.any? { |p| p.name == name }
        raise Error, "A project named '#{name}' is already registered. " \
                     "Pick another with --name."
      end

      save(entries + [{ "name" => name, "path" => root }])
      [:added, projects.find { |p| p.path == root }]
    end

    private

    def data
      return {} unless File.exist?(@file)

      YAML.safe_load_file(@file) || {}
    end

    def entries
      data.fetch("projects", nil) || []
    end

    # Keeps any other top-level keys (like defaults) as they were.
    def save(list)
      FileUtils.mkdir_p(File.dirname(@file))
      File.write(@file, YAML.dump(data.merge("projects" => list)))
    end

    def git_root(path)
      dir = File.expand_path(path)
      raise Error, "No such directory: #{dir}" unless File.directory?(dir)

      out, status = Open3.capture2e("git", "-C", dir, "rev-parse", "--show-toplevel")
      raise Error, "Not a git repository: #{dir}" unless status.success?

      out.strip
    end
  end
end
