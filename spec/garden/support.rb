# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/garden"

# Points garden's config, state, data, and Claude folders at a temp folder.
RSpec.shared_context "garden sandbox" do
  around do |example|
    Dir.mktmpdir("garden-spec") do |dir|
      @sandbox = File.realpath(dir)
      vars = {
        "XDG_CONFIG_HOME" => File.join(@sandbox, "config"),
        "XDG_STATE_HOME" => File.join(@sandbox, "state"),
        "XDG_DATA_HOME" => File.join(@sandbox, "data"),
        "CLAUDE_CONFIG_DIR" => File.join(@sandbox, "claude")
      }
      old = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      vars.each { |k, v| ENV[k] = v }
      begin
        example.run
      ensure
        old.each { |k, v| ENV[k] = v }
      end
    end
  end

  attr_reader :sandbox

  def make_git_repo(name)
    path = File.join(sandbox, "projects", name)
    FileUtils.mkdir_p(path)
    system("git", "init", "-q", path, exception: true)
    path
  end
end
