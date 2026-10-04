# syntax=docker/dockerfile:1
FROM ruby:3.4-slim

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Gemfile first for layer caching
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Copy application source
COPY . .

# Port 8888 is used for the Spotify OAuth2 callback
EXPOSE 8888

# Run as interactive terminal app
CMD ["bundle", "exec", "ruby", "main.rb"]
