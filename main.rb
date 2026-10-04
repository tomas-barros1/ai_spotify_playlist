#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'optparse'
require_relative 'lib/spotify_client'
require_relative 'lib/spotify_auth'
require_relative 'lib/playlist_generator'

def print_banner
  puts <<~BANNER
    ========================================================
     🎧 AI Spotify Playlist Generator & Manager (Ruby) 🎧
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
    warn '❌ A Gemini API key is required. Exiting.'
    exit 1
  end

  ENV['GEMINI_API_KEY'] = key
  save_to_env('GEMINI_API_KEY', key)
  key
end

def save_to_env(key, value)
  env_path = File.expand_path('.env', __dir__)
  content = File.exist?(env_path) ? File.read(env_path) : ''
  updated = if content.match?(/^#{key}=/)
              content.sub(/^#{key}=.*$/, "#{key}=#{value}")
            else
              "#{content.strip}\n#{key}=#{value}\n"
            end
  File.write(env_path, updated)
  puts "💾 Saved #{key} to .env"
end

def ensure_spotify_credentials
  client_id = ENV['SPOTIFY_CLIENT_ID']&.strip
  client_secret = ENV['SPOTIFY_CLIENT_SECRET']&.strip

  # If Client ID and Secret are already set, use them
  if client_id && !client_id.empty? && client_secret && !client_secret.empty?
    return { client_id: client_id, client_secret: client_secret }
  end

  # Fallback: check if user still has a manual SPOTIFY_ACCESS_TOKEN
  if ENV['SPOTIFY_ACCESS_TOKEN'] && !ENV['SPOTIFY_ACCESS_TOKEN'].strip.empty?
    return { token: ENV['SPOTIFY_ACCESS_TOKEN'].strip }
  end

  puts "\n========================================================"
  puts " 🔑 Spotify Developer Credentials Required"
  puts "========================================================"
  puts "To avoid Spotify rate limits and enable automatic login:"
  puts "1. Go to Spotify Developer Dashboard:"
  puts "   https://developer.spotify.com/dashboard"
  puts "2. Click 'Create app':"
  puts "   - App name: AI Spotify Playlist"
  puts "   - App description: Terminal playlist generator"
  puts "   - Redirect URI: http://127.0.0.1:8888/callback (REQUIRED)"
  puts "   - Which API/SDKs are you planning to use: Web API"
  puts "3. Save and go to Settings to copy your Client ID and Client Secret."
  puts "========================================================\n"

  print "Enter your SPOTIFY_CLIENT_ID: "
  client_id = $stdin.gets&.strip
  if client_id.nil? || client_id.empty?
    warn "❌ SPOTIFY_CLIENT_ID is required. Exiting."
    exit 1
  end

  print "Enter your SPOTIFY_CLIENT_SECRET: "
  client_secret = $stdin.gets&.strip
  if client_secret.nil? || client_secret.empty?
    warn "❌ SPOTIFY_CLIENT_SECRET is required. Exiting."
    exit 1
  end

  ENV['SPOTIFY_CLIENT_ID'] = client_id
  ENV['SPOTIFY_CLIENT_SECRET'] = client_secret
  save_to_env('SPOTIFY_CLIENT_ID', client_id)
  save_to_env('SPOTIFY_CLIENT_SECRET', client_secret)

  { client_id: client_id, client_secret: client_secret }
end

def init_spotify_client
  creds = ensure_spotify_credentials

  if creds[:client_id] && creds[:client_secret]
    refresh_token = ENV['SPOTIFY_REFRESH_TOKEN']&.strip
    auth = SpotifyAuth.new(
      client_id: creds[:client_id],
      client_secret: creds[:client_secret],
      refresh_token: refresh_token,
      on_token_refresh: lambda do |new_token|
        ENV['SPOTIFY_REFRESH_TOKEN'] = new_token
        save_to_env('SPOTIFY_REFRESH_TOKEN', new_token)
      end
    )
    client = SpotifyClient.new(auth: auth)
  else
    client = SpotifyClient.new(token: creds[:token])
  end

  user = client.current_user
  user_name = user['display_name'] || user['id']
  puts "👤 Connected as Spotify user: #{user_name} (#{user['id']})"
  client
rescue SpotifyAuth::Error => e
  warn "\n❌ Authentication failed: #{e.message}"
  exit 1
rescue StandardError => e
  warn "\n❌ Could not connect to Spotify: #{e.message}"
  exit 1
end

# Option 1: Create a new playlist from prompt
def create_playlist_flow(spotify, gemini_key, default_model)
  puts "\n--------------------------------------------------------"
  puts " 🎵 Option 1: Create a New Playlist with Gemini AI"
  puts "--------------------------------------------------------"
  puts "💡 Example ideas:"
  puts "   - 'High energy synthwave for night driving'"
  puts "   - 'Mellow acoustic indie folk for a rainy afternoon'"
  puts "   - 'Late 90s alternative rock workout'"
  puts "   - 'Bossa nova and chill jazz for studying'"
  print "\n🎙️  Enter your playlist prompt/idea: "
  prompt = $stdin.gets&.strip

  if prompt.nil? || prompt.empty?
    puts "⚠️ No prompt entered. Returning to menu."
    return
  end

  print "💿 Number of tracks to curate (default 10): "
  track_count_input = $stdin.gets&.strip
  track_count = track_count_input.empty? ? 10 : [track_count_input.to_i, 1].max

  print "🌐 Make playlist public? (y/N): "
  is_public = %w[y yes].include?($stdin.gets&.strip&.downcase)

  puts "\n⏳ Asking Gemini (#{default_model}) to curate your playlist..."
  generator = PlaylistGenerator.new(api_key: gemini_key, model: default_model)

  curated = begin
    generator.generate(prompt, track_count: track_count)
  rescue StandardError => e
    warn "❌ Failed to generate with Gemini: #{e.message}"
    return
  end

  puts "\n📋 Gemini Curated Tracklist:"
  puts "   Title:       #{curated[:name]}"
  puts "   Description: #{curated[:description]}"
  puts "   Tracks (#{curated[:tracks].size}):"
  curated[:tracks].each_with_index do |t, i|
    puts "     #{format('%2d', i + 1)}. #{t[:title]} - #{t[:artist]}"
  end

  puts "\n🔍 Searching Spotify for tracks..."
  found_tracks = []
  curated[:tracks].each_with_index do |track_info, idx|
    print "   [#{idx + 1}/#{curated[:tracks].size}] #{track_info[:title]} - #{track_info[:artist]} ... "
    result = spotify.search_track(track_info[:title], track_info[:artist])
    if result
      puts "✓ (#{result[:name]} by #{result[:artist]})"
      found_tracks << result
    else
      puts "✗ (Not found, skipped)"
    end
  end

  if found_tracks.empty?
    warn "❌ No tracks could be found on Spotify. Returning to menu."
    return
  end

  puts "\n✨ Creating playlist on Spotify..."
  desc_attr = "#{curated[:description]} [Generated with Gemini & RubyLLM]"
  playlist = spotify.create_playlist(
    name: curated[:name],
    description: desc_attr,
    is_public: is_public
  )

  puts "   Created playlist: '#{playlist[:name]}' (ID: #{playlist[:id]})"
  puts "➕ Adding #{found_tracks.size} tracks to Spotify..."
  spotify.add_tracks(playlist[:id], found_tracks.map { |t| t[:uri] })

  puts <<~SUCCESS

    ========================================================
     🎉 SUCCESS! Your playlist is live on Spotify!
    ========================================================
     🎵 Name:   #{playlist[:name]}
     📝 About:  #{curated[:description]}
     💿 Tracks: #{found_tracks.size} added
     🔗 Link:   #{playlist[:url]}
    ========================================================
  SUCCESS
end

# Display a table of playlists
def print_playlists_table(playlists, title = "Your Playlists")
  puts "\n========================================================"
  puts " #{title} (#{playlists.size} shown)"
  puts "========================================================"
  puts format(" %4s | %-40s | %-6s | %s", "#", "Name", "Tracks", "Type")
  puts "------+------------------------------------------+--------+------------------"

  playlists.each_with_index do |p, i|
    truncated_name = p[:name].length > 40 ? "#{p[:name][0...37]}..." : p[:name]
    type_label = p[:collaborative] ? "collab" : "owned"
    puts format(" %4d | %-40s | %-6s | %s", i + 1, truncated_name, p[:total_tracks], type_label)
  end
  puts "========================================================"
end

# Option 2: Edit an existing playlist
def edit_playlist_flow(spotify, gemini_key, default_model)
  puts "\n📥 Fetching your editable playlists..."
  all_playlists = begin
    spotify.user_playlists(editable_only: true)
  rescue StandardError => e
    warn "❌ Could not fetch playlists: #{e.message}"
    return
  end

  if all_playlists.empty?
    puts "No editable playlists found. Create one first with Option 1!"
    return
  end

  current_list = all_playlists
  is_filtered = false

  loop do
    title = is_filtered ? "🔍 Filtered Results" : "✏️  My Editable Playlists"
    print_playlists_table(current_list, title)

    puts "\nActions:"
    puts "  • Enter a playlist NUMBER (1-#{current_list.size}) to select it"
    puts "  • Type a search term (e.g. 'rock' or 's jazz') to filter by name"
    puts "  • Type 'all' to show all #{all_playlists.size} playlists"
    puts "  • Type '0', 'q', or 'back' to return to Main Menu"

    print "\n👉 Select playlist or search by name: "
    input = $stdin.gets&.strip

    break if input.nil? || %w[0 q back exit].include?(input.downcase)

    if input.downcase == 'all'
      current_list = all_playlists
      is_filtered = false
      next
    end

    # Check if user entered a number to select from current list
    if input.match?(/^\d+$/)
      idx = input.to_i - 1
      if idx >= 0 && idx < current_list.size
        selected = current_list[idx]
        playlist_editor_menu(spotify, selected, gemini_key, default_model)
        # Refresh playlist list after editing
        all_playlists = (spotify.user_playlists rescue all_playlists)
        current_list = is_filtered ? all_playlists.select { |p| p[:name].downcase.include?(input.downcase) } : all_playlists
        next
      else
        puts "⚠️ Invalid playlist number. Please select between 1 and #{current_list.size}."
        next
      end
    end

    # Otherwise, treat as search query by playlist name
    query = input.sub(/^s\s+/i, '').strip.downcase
    matches = all_playlists.select { |p| p[:name].downcase.include?(query) }

    if matches.empty?
      puts "\n⚠️ No playlists found matching \"#{query}\". Showing full list."
      current_list = all_playlists
      is_filtered = false
    else
      current_list = matches
      is_filtered = true
    end
  end
end

# Sub-menu for a selected playlist
def playlist_editor_menu(spotify, playlist, gemini_key, default_model)
  loop do
    puts "\n========================================================"
    puts " 🎵 Managing Playlist: \"#{playlist[:name]}\""
    puts " 💿 Total Tracks: #{playlist[:total_tracks]} | Owner: #{playlist[:owner]}"
    puts " 🔗 URL: #{playlist[:url]}"
    puts "========================================================"
    puts "  [1] 🤖 Add more tracks with Gemini AI (prompt-based)"
    puts "  [2] ➕ Add a track manually (search title/artist)"
    puts "  [3] 📄 View tracks in this playlist"
    puts "  [4] ❌ Remove tracks from this playlist"
    puts "  [5] ✏️  Edit playlist name & description"
    puts "  [0] 🔙 Back to Playlists List"
    print "\nEnter choice (1-5 or 0): "

    choice = $stdin.gets&.strip

    case choice
    when '1'
      add_tracks_with_ai(spotify, playlist, gemini_key, default_model)
    when '2'
      add_track_manually(spotify, playlist)
    when '3'
      view_playlist_tracks(spotify, playlist)
    when '4'
      remove_playlist_tracks(spotify, playlist)
    when '5'
      edit_playlist_details(spotify, playlist)
    when '0', 'q', 'back'
      break
    else
      puts "⚠️ Invalid option. Please choose 1-5 or 0."
    end
  end
end

# Edit Action 1: Add tracks using Gemini
def add_tracks_with_ai(spotify, playlist, gemini_key, default_model)
  puts "\n🤖 Add Tracks with Gemini AI"
  print "What vibe or songs do you want to add to '#{playlist[:name]}'? "
  prompt = $stdin.gets&.strip
  return if prompt.nil? || prompt.empty?

  print "How many songs to add? (default 5): "
  count_input = $stdin.gets&.strip
  count = count_input.empty? ? 5 : [count_input.to_i, 1].max

  puts "\n⏳ Consulting Gemini (#{default_model})..."
  generator = PlaylistGenerator.new(api_key: gemini_key, model: default_model)
  full_prompt = "For the existing playlist titled '#{playlist[:name]}', suggest #{count} additional songs that fit this request: #{prompt}"

  curated = begin
    generator.generate(full_prompt, track_count: count)
  rescue StandardError => e
    warn "❌ Gemini error: #{e.message}"
    return
  end

  puts "\n📋 Gemini Recommended:"
  curated[:tracks].each_with_index do |t, i|
    puts "  #{i + 1}. #{t[:title]} - #{t[:artist]}"
  end

  print "\nDo you want to search and add these tracks to '#{playlist[:name]}'? (Y/n): "
  return if %w[n no].include?($stdin.gets&.strip&.downcase)

  found_uris = []
  curated[:tracks].each do |t|
    print "Searching for #{t[:title]} - #{t[:artist]}... "
    match = spotify.search_track(t[:title], t[:artist])
    if match
      puts "✓ (#{match[:name]})"
      found_uris << match[:uri]
    else
      puts "✗ Not found"
    end
  end

  if found_uris.any?
    spotify.add_tracks(playlist[:id], found_uris)
    playlist[:total_tracks] = (playlist[:total_tracks] || 0) + found_uris.size
    puts "🎉 Added #{found_uris.size} new tracks to '#{playlist[:name]}'!"
  else
    puts "⚠️ No matching tracks were found on Spotify."
  end
end

# Edit Action 2: Add a single track manually
def add_track_manually(spotify, playlist)
  puts "\n➕ Add Track Manually"
  print "Enter song title: "
  title = $stdin.gets&.strip
  return if title.nil? || title.empty?

  print "Enter artist name (optional): "
  artist = $stdin.gets&.strip

  puts "🔍 Searching Spotify..."
  match = spotify.search_track(title, artist)

  if match.nil?
    puts "❌ No match found on Spotify for '#{title}'."
    return
  end

  puts "Found: #{match[:name]} by #{match[:artist]}"
  print "Add this track to '#{playlist[:name]}'? (Y/n): "
  return if %w[n no].include?($stdin.gets&.strip&.downcase)

  spotify.add_tracks(playlist[:id], [match[:uri]])
  playlist[:total_tracks] = (playlist[:total_tracks] || 0) + 1
  puts "🎉 Track added successfully!"
end

# Edit Action 3: View playlist tracks
def view_playlist_tracks(spotify, playlist)
  puts "\n📄 Fetching tracks for '#{playlist[:name]}'..."
  tracks = begin
    spotify.playlist_tracks(playlist[:id])
  rescue StandardError => e
    warn "❌ Failed to fetch tracks: #{e.message}"
    return
  end

  if tracks.empty?
    puts "This playlist is currently empty."
    return
  end

  puts "\n========================================================"
  puts " Tracks in \"#{playlist[:name]}\" (#{tracks.size} total)"
  puts "========================================================"
  tracks.each_with_index do |t, i|
    puts format(" %3d | %-38s | %s", i + 1, t[:name][0...38], t[:artist])
  end
  puts "========================================================"
  print "\nPress Enter to return to playlist menu..."
  $stdin.gets
end

# Edit Action 4: Remove tracks
def remove_playlist_tracks(spotify, playlist)
  puts "\n❌ Remove Tracks from '#{playlist[:name]}'"
  tracks = begin
    spotify.playlist_tracks(playlist[:id])
  rescue StandardError => e
    warn "❌ Failed to fetch tracks: #{e.message}"
    return
  end

  if tracks.empty?
    puts "This playlist has no tracks to remove."
    return
  end

  tracks.each_with_index do |t, i|
    puts format(" [%2d] %-38s - %s", i + 1, t[:name][0...38], t[:artist])
  end

  print "\nEnter track numbers to remove (e.g. 1, 3, 5) or '0' to cancel: "
  input = $stdin.gets&.strip
  return if input.nil? || input.empty? || input == '0'

  indices = input.split(',').map { |s| s.strip.to_i - 1 }.select { |i| i >= 0 && i < tracks.size }
  if indices.empty?
    puts "⚠️ No valid track numbers selected."
    return
  end

  to_remove = indices.map { |i| tracks[i] }
  puts "\nSelected for removal:"
  to_remove.each { |t| puts "  - #{t[:name]} by #{t[:artist]}" }
  print "Are you sure you want to remove these #{to_remove.size} tracks? (y/N): "
  return unless %w[y yes].include?($stdin.gets&.strip&.downcase)

  spotify.remove_tracks(playlist[:id], to_remove.map { |t| t[:uri] })
  playlist[:total_tracks] = [((playlist[:total_tracks] || 0) - to_remove.size), 0].max
  puts "🗑️ Removed #{to_remove.size} tracks from '#{playlist[:name]}'."
end

# Edit Action 5: Edit playlist name & description
def edit_playlist_details(spotify, playlist)
  puts "\n✏️  Edit Playlist Name & Description"
  puts "Current Name:        #{playlist[:name]}"
  puts "Current Description: #{playlist[:description]}"

  print "\nNew name (press Enter to keep current): "
  new_name = $stdin.gets&.strip
  new_name = nil if new_name.nil? || new_name.empty?

  print "New description (press Enter to keep current): "
  new_desc = $stdin.gets&.strip
  new_desc = nil if new_desc.nil? || new_desc.empty?

  if new_name.nil? && new_desc.nil?
    puts "No changes made."
    return
  end

  spotify.update_playlist(playlist[:id], name: new_name, description: new_desc)
  playlist[:name] = new_name if new_name
  playlist[:description] = new_desc if new_desc
  puts "✅ Playlist details updated successfully!"
end

# Main Program Loop
def main
  options = {
    model: ENV.fetch('GEMINI_MODEL', 'gemini-3.8-flash')
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby main.rb [options]'
    opts.on('-m', '--model MODEL', String, 'Gemini model to use (default: gemini-3.8-flash)') do |m|
      options[:model] = m
    end
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit 0
    end
  end.parse!

  print_banner

  gemini_key = ensure_gemini_key
  spotify = init_spotify_client

  # Main Menu
  loop do
    puts "\n========================================================"
    puts " 📋 Main Menu"
    puts "========================================================"
    puts "  [1] 🎵 Create a new playlist (from Gemini AI prompt)"
    puts "  [2] ✏️  Edit an existing playlist (show all & search by name)"
    puts "  [0] 🚪 Exit"
    print "\nEnter your choice (1, 2, or 0): "

    choice = $stdin.gets&.strip

    case choice
    when '1'
      create_playlist_flow(spotify, gemini_key, options[:model])
    when '2'
      edit_playlist_flow(spotify, gemini_key, options[:model])
    when '0', 'q', 'exit'
      puts "\n👋 Goodbye! Happy listening!"
      break
    else
      puts "⚠️ Invalid option. Please select 1, 2, or 0."
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  main
end
