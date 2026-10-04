#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'optparse'
require_relative 'lib/spotify_client'
require_relative 'lib/playlist_generator'

def print_banner
  puts <<~BANNER
    ========================================================
     🎧 AI Spotify Playlist Generator (Ruby + RubyLLM) 🎧
    ========================================================
  BANNER
end

def ensure_gemini_key
  key = ENV['GEMINI_API_KEY']&.strip
  return key if key && !key.empty?

  puts "\n🔑 Gemini API key not found in .env or environment."
  print "Enter your Gemini API key (from https://aistudio.google.com/): "
  key = $stdin.gets&.strip

  if key.nil? || key.empty?
    warn "❌ A Gemini API key is required. Exiting."
    exit 1
  end

  ENV['GEMINI_API_KEY'] = key

  # Save to .env for convenience if .env exists
  env_path = File.expand_path('.env', __dir__)
  if File.exist?(env_path)
    content = File.read(env_path)
    updated = if content.match?(/^GEMINI_API_KEY=/)
                content.sub(/^GEMINI_API_KEY=.*$/, "GEMINI_API_KEY=#{key}")
              else
                "#{content.strip}\nGEMINI_API_KEY=#{key}\n"
              end
    File.write(env_path, updated)
    puts "💾 Saved GEMINI_API_KEY to .env for future runs."
  end

  key
end

def ensure_spotify_token
  token = ENV['SPOTIFY_ACCESS_TOKEN']&.strip
  return token if token && !token.empty?

  # Check main.js fallback if present
  main_js_path = File.expand_path('main.js', __dir__)
  if File.exist?(main_js_path)
    match = File.read(main_js_path).match(/const token = '([^']+)'/)
    return match[1].strip if match && !match[1].strip.empty?
  end

  puts "\n🎵 Spotify Access Token not found."
  puts "Get one with 'playlist-modify-public' and 'playlist-modify-private' scopes from:"
  puts "https://developer.spotify.com/documentation/web-api/tutorials/getting-started#request-an-access-token"
  print "Enter your Spotify Access Token: "
  token = $stdin.gets&.strip

  if token.nil? || token.empty?
    warn "❌ A Spotify access token is required. Exiting."
    exit 1
  end

  ENV['SPOTIFY_ACCESS_TOKEN'] = token
  token
end

def main
  options = {
    tracks: 10,
    public: false,
    model: ENV.fetch('GEMINI_MODEL', 'gemini-3.8-flash')
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby main.rb [options] ["playlist prompt / theme"]'

    opts.on('-n', '--tracks COUNT', Integer, 'Number of tracks to generate (default: 10)') do |n|
      options[:tracks] = n
    end

    opts.on('-p', '--public', 'Make the playlist public on Spotify (default: private)') do
      options[:public] = true
    end

    opts.on('-m', '--model MODEL', String, 'Gemini model to use (default: gemini-3.8-flash)') do |m|
      options[:model] = m
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit 0
    end
  end

  parser.parse!

  print_banner

  gemini_key = ensure_gemini_key
  spotify_token = ensure_spotify_token

  # Initialize Spotify client and verify access
  puts "\n📡 Connecting to Spotify..."
  spotify = SpotifyClient.new(token: spotify_token)
  user = begin
    spotify.current_user
  rescue SpotifyClient::AuthenticationError => e
    warn "\n❌ #{e.message}"
    warn 'Spotify tokens expire in 1 hour. Get a fresh token from:'
    warn 'https://developer.spotify.com/documentation/web-api/tutorials/getting-started#request-an-access-token'
    warn 'Then update SPOTIFY_ACCESS_TOKEN in .env.'
    exit 1
  rescue StandardError => e
    warn "\n❌ Could not connect to Spotify: #{e.message}"
    exit 1
  end

  user_name = user['display_name'] || user['id']
  puts "👤 Logged in as: #{user_name} (#{user['id']})"

  # Get user prompt
  prompt = ARGV.join(' ').strip
  if prompt.empty?
    puts "\n💡 Example ideas:"
    puts "   - 'High energy synthwave for night driving'"
    puts "   - 'Mellow acoustic indie folk for a rainy afternoon'"
    puts "   - 'Late 90s alternative rock workout'"
    puts "   - 'Bossa nova and chill jazz for studying'\n"
    print '🎙️  What kind of playlist do you want to create? '
    prompt = $stdin.gets&.strip
  end

  if prompt.nil? || prompt.empty?
    warn '❌ No prompt provided. Exiting.'
    exit 1
  end

  puts "\n🤖 Prompt: \"#{prompt}\""
  puts "⏳ Consulting Gemini (#{options[:model]}) via RubyLLM..."

  generator = PlaylistGenerator.new(api_key: gemini_key, model: options[:model])
  curated = begin
    generator.generate(prompt, track_count: options[:tracks])
  rescue StandardError => e
    warn "\n❌ Failed to generate playlist with Gemini: #{e.message}"
    exit 1
  end

  puts "\n📋 Gemini curated:"
  puts "   Title:       #{curated[:name]}"
  puts "   Description: #{curated[:description]}"
  puts "   Tracks (#{curated[:tracks].size}):"
  curated[:tracks].each_with_index do |t, i|
    puts "     #{format('%2d', i + 1)}. #{t[:title]} - #{t[:artist]}"
  end

  puts "\n🔍 Searching Spotify for matching tracks..."
  found_tracks = []
  curated[:tracks].each_with_index do |track_info, idx|
    print "   [#{idx + 1}/#{curated[:tracks].size}] #{track_info[:title]} - #{track_info[:artist]} ... "
    result = spotify.search_track(track_info[:title], track_info[:artist])
    if result
      puts "✓ (#{result[:name]} by #{result[:artist]})"
      found_tracks << result
    else
      puts '✗ (Not found on Spotify, skipping)'
    end
  end

  if found_tracks.empty?
    warn "\n❌ None of the suggested tracks could be found on Spotify. Please try a different prompt."
    exit 1
  end

  puts "\n✨ Creating playlist on Spotify..."
  description_with_attribution = "#{curated[:description]} [Generated with Gemini & RubyLLM]"
  playlist = spotify.create_playlist(
    name: curated[:name],
    description: description_with_attribution,
    is_public: options[:public]
  )

  puts "   Playlist created: '#{playlist[:name]}' (ID: #{playlist[:id]})"

  puts "➕ Adding #{found_tracks.size} tracks to the playlist..."
  spotify.add_tracks(playlist[:id], found_tracks.map { |t| t[:uri] })

  puts <<~SUCCESS

    ========================================================
     🎉 SUCCESS! Your playlist is ready on Spotify!
    ========================================================
     🎵 Name:   #{playlist[:name]}
     📝 About:  #{curated[:description]}
     💿 Tracks: #{found_tracks.size} added
     🔗 Link:   #{playlist[:url]}
    ========================================================
  SUCCESS
end

if __FILE__ == $PROGRAM_NAME
  main
end
