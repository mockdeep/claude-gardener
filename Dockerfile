FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    nodejs \
    npm \
    build-essential \
    libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (Claude CLI refuses --dangerously-skip-permissions as root)
RUN useradd -m -s /bin/bash gardener
ENV HOME=/home/gardener

# Install Claude Code CLI via npm
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /action
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

COPY . .
RUN chmod +x /action/entrypoint.sh

# Switch to non-root user
USER gardener

ENTRYPOINT ["/action/entrypoint.sh"]
