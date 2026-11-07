# frozen_string_literal: true

module Garden
  # Guesses how to run a project's tests from the files it has.
  module TestCommands
    module_function

    def for(project)
      project.test_commands || guess(project.path)
    end

    def guess(path)
      has = ->(file) { File.exist?(File.join(path, file)) }
      if has["Gemfile"]
        [has["spec"] ? "bundle exec rspec" : "bundle exec rake test"]
      elsif has["package.json"] then ["npm test"]
      elsif has["pyproject.toml"] then ["pytest"]
      elsif has["Cargo.toml"] then ["cargo test"]
      elsif has["go.mod"] then ["go test ./..."]
      else []
      end
    end
  end
end
