# frozen_string_literal: true

require "octokit"

module ClaudeGardener
  class GithubClient
    def initialize(token: nil, repository: nil)
      @token = token || ENV.fetch("GITHUB_TOKEN")
      @repository = repository || ENV.fetch("GITHUB_REPOSITORY")
      @client = Octokit::Client.new(access_token: @token)
      @client.auto_paginate = false
    end

    attr_reader :repository

    def pull_requests(state: "open", labels: nil)
      options = { state: state }
      prs = @client.pull_requests(@repository, **options)

      if labels
        prs.select do |pr|
          pr_labels = pr.labels.map(&:name)
          labels.all? { |label| pr_labels.include?(label) }
        end
      else
        prs
      end
    end

    def pull_request(number)
      @client.pull_request(@repository, number)
    end

    def pull_request_files(number)
      @client.pull_request_files(@repository, number)
    end

    def review_comments(pr_number)
      @client.pull_request_comments(@repository, pr_number)
    end

    def issue_comments(pr_number)
      @client.issue_comments(@repository, pr_number)
    end

    def create_pull_request(base:, head:, title:, body:)
      @client.create_pull_request(@repository, base, head, title, body)
    end

    def add_labels(pr_number, labels)
      @client.add_labels_to_an_issue(@repository, pr_number, labels)
    end

    def add_comment(pr_number, body)
      @client.add_comment(@repository, pr_number, body)
    end

    def update_comment(comment_id, body)
      @client.update_comment(@repository, comment_id, body)
    end

    def create_branch(branch_name, from: nil)
      from ||= default_branch
      ref = @client.ref(@repository, "heads/#{from}")
      sha = ref.object.sha

      @client.create_ref(@repository, "refs/heads/#{branch_name}", sha)
    end

    def delete_branch(branch_name)
      @client.delete_ref(@repository, "heads/#{branch_name}")
    rescue Octokit::UnprocessableEntity
      # Branch may not exist, ignore
    end

    def default_branch
      @default_branch ||= @client.repository(@repository).default_branch
    end

    def ensure_label_exists(name, color: "0e8a16", description: nil)
      @client.label(@repository, name)
    rescue Octokit::NotFound
      @client.add_label(@repository, name, color, description: description)
    end
  end
end
