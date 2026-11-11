# frozen_string_literal: true

require "fileutils"

module Garden
  # Links the skills in this repo into Claude Code's skills folder, so they
  # work from any project and pick up edits right away.
  class Setup
    SKILLS = %w[garden-review].freeze

    def initialize(source_dir: Paths.bundled_skills_dir, target_dir: Paths.claude_skills_dir)
      @source_dir = source_dir
      @target_dir = target_dir
    end

    # Returns a list of [skill, status] pairs, where status is :linked or
    # :already_linked. Raises if something else is in the way.
    def run
      FileUtils.mkdir_p(@target_dir)
      SKILLS.map { |skill| [skill, link(skill)] }
    end

    # Skills Claude can't find, including links that point nowhere.
    def missing
      SKILLS.reject { |skill| File.exist?(File.join(@target_dir, skill)) }
    end

    private

    def link(skill)
      source = File.join(@source_dir, skill)
      target = File.join(@target_dir, skill)

      if File.symlink?(target)
        return :already_linked if File.readlink(target) == source

        raise Error, "#{target} already links to #{File.readlink(target)}. " \
                     "Remove it and run setup again."
      end
      raise Error, "#{target} already exists. Remove it and run setup again." if File.exist?(target)

      File.symlink(source, target)
      :linked
    end
  end
end
