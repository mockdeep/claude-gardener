# frozen_string_literal: true

module Garden
  # Where garden keeps its files. Follows the XDG base directory spec so tests
  # (and users) can move everything by setting environment variables.
  module Paths
    module_function

    def config_dir
      File.join(xdg("XDG_CONFIG_HOME", ".config"), "garden")
    end

    def state_dir
      File.join(xdg("XDG_STATE_HOME", ".local/state"), "garden")
    end

    def data_dir
      File.join(xdg("XDG_DATA_HOME", ".local/share"), "garden")
    end

    def projects_file
      File.join(config_dir, "projects.yml")
    end

    # Lessons from past reviews that apply to every project.
    def guidance_dir
      File.join(config_dir, "guidance")
    end

    # Summaries written by the garden-review skill, one per finding.
    def reviews_dir
      File.join(state_dir, "reviews")
    end

    # Test output saved when a fix's tests fail, one per finding.
    def logs_dir
      File.join(state_dir, "logs")
    end

    def worktrees_dir
      File.join(data_dir, "worktrees")
    end

    # Claude Code's own config folder. CLAUDE_CONFIG_DIR is the variable Claude
    # Code itself reads to move it.
    def claude_dir
      env("CLAUDE_CONFIG_DIR") || File.join(Dir.home, ".claude")
    end

    def claude_skills_dir
      File.join(claude_dir, "skills")
    end

    # Skills shipped in this repo.
    def bundled_skills_dir
      File.expand_path("../../skills", __dir__)
    end

    def xdg(var, default)
      env(var) || File.join(Dir.home, default)
    end

    # Empty values count as unset, as the XDG spec says.
    def env(var)
      value = ENV.fetch(var, nil)
      value unless value.nil? || value.empty?
    end
  end
end
