# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class SpotifyClient
  BASE_URL = 'https://api.spotify.com'

  class AuthenticationError < StandardError; end
  class ApiError < StandardError; end

  attr_reader :token

  def initialize(token:)
    @token = token&.strip
    raise AuthenticationError, 'Spotify access token cannot be empty.' if @token.nil? || @token.empty?
  end

  # Searches for a track on Spotify using track title and optional artist.
  # Returns a hash with track info or nil if not found.
  def search_track(title, artist = nil)
    # Attempt 1: Strict search using track: and artist: field filters
    query = if artist && !artist.strip.empty?
              "track:\"#{title.strip}\" artist:\"#{artist.strip}\""
            else
              "track:\"#{title.strip}\""
            end

    result = execute_search(query)
    return result if result

    # Attempt 2: Loose search with title and artist combined
    if artist && !artist.strip.empty?
      result = execute_search("#{title.strip} #{artist.strip}")
      return result if result
    end

    # Attempt 3: Just the title if everything else failed
    execute_search(title.strip)
  end

  # Creates a playlist for the current authorized Spotify user (matches main.js POST v1/me/playlists).
  def create_playlist(name:, description:, is_public: false)
    body = {
      name: name,
      description: description,
      public: is_public
    }

    data = fetch_web_api('v1/me/playlists', :post, body)
    {
      id: data['id'],
      name: data['name'],
      description: data['description'],
      url: data.dig('external_urls', 'spotify'),
      uri: data['uri']
    }
  end

  # Adds tracks to a playlist using the Spotify Web API (matches main.js POST v1/playlists/{id}/items?uris=...).
  def add_tracks(playlist_id, track_uris)
    return [] if track_uris.nil? || track_uris.empty?

    # Spotify supports up to 100 tracks per batch
    track_uris.each_slice(50) do |batch|
      uris_param = batch.join(',')
      fetch_web_api("v1/playlists/#{playlist_id}/items?uris=#{uris_param}", :post)
    end

    track_uris
  end

  # Fetches all playlists owned or followed by current user
  def user_playlists(limit: 50)
    all_playlists = []
    offset = 0

    loop do
      data = fetch_web_api("v1/me/playlists?limit=#{limit}&offset=#{offset}", :get)
      items = data['items'] || []
      break if items.empty?

      all_playlists.concat(items)
      offset += items.size
      break if offset >= (data['total'] || 0)
    end

    all_playlists.map do |p|
      {
        id: p['id'],
        name: p['name'],
        description: p['description'],
        owner: p.dig('owner', 'display_name') || p.dig('owner', 'id'),
        owner_id: p.dig('owner', 'id'),
        total_tracks: p.dig('items', 'total') || p.dig('tracks', 'total') || 0,
        url: p.dig('external_urls', 'spotify'),
        uri: p['uri'],
        public: p['public']
      }
    end
  end

  # Retrieves single playlist details
  def get_playlist(playlist_id)
    data = fetch_web_api("v1/playlists/#{playlist_id}", :get)
    {
      id: data['id'],
      name: data['name'],
      description: data['description'],
      owner: data.dig('owner', 'display_name') || data.dig('owner', 'id'),
      owner_id: data.dig('owner', 'id'),
      total_tracks: data.dig('items', 'total') || data.dig('tracks', 'total') || 0,
      url: data.dig('external_urls', 'spotify'),
      uri: data['uri'],
      public: data['public']
    }
  end

  # Fetches tracks for a playlist
  def playlist_tracks(playlist_id, limit: 100)
    tracks = []
    offset = 0

    loop do
      data = fetch_web_api("v1/playlists/#{playlist_id}/items?limit=#{limit}&offset=#{offset}", :get)
      items = data['items'] || []
      break if items.empty?

      items.each do |item|
        track = item['track'] || item['item']
        next unless track && track['id']

        tracks << {
          id: track['id'],
          uri: track['uri'],
          name: track['name'],
          artist: (track['artists'] || []).map { |a| a['name'] }.join(', '),
          album: track.dig('album', 'name'),
          duration_ms: track['duration_ms']
        }
      end

      offset += items.size
      break if offset >= (data['total'] || 0)
    end

    tracks
  end

  # Updates a playlist's name and/or description
  def update_playlist(playlist_id, name: nil, description: nil, is_public: nil)
    body = {}
    body[:name] = name if name && !name.strip.empty?
    body[:description] = description if description
    body[:public] = is_public unless is_public.nil?

    fetch_web_api("v1/playlists/#{playlist_id}", :put, body)
    true
  end

  # Removes specified tracks from a playlist
  def remove_tracks(playlist_id, track_uris)
    return [] if track_uris.nil? || track_uris.empty?

    track_uris.each_slice(100) do |batch|
      body = { tracks: batch.map { |u| { uri: u } } }
      fetch_web_api("v1/playlists/#{playlist_id}/items", :delete, body)
    end

    track_uris
  end

  # Gets current user's profile to verify token and retrieve user name
  def current_user
    fetch_web_api('v1/me', :get)
  end

  private

  def execute_search(query)
    encoded_query = URI.encode_www_form_component(query)
    data = fetch_web_api("v1/search?q=#{encoded_query}&type=track&limit=1", :get)
    track = data.dig('tracks', 'items', 0)
    return nil unless track

    {
      id: track['id'],
      uri: track['uri'],
      name: track['name'],
      artist: (track['artists'] || []).map { |a| a['name'] }.join(', '),
      album: track.dig('album', 'name'),
      url: track.dig('external_urls', 'spotify')
    }
  rescue ApiError
    nil
  end

  def fetch_web_api(endpoint, method, body = nil)
    uri = URI("#{BASE_URL}/#{endpoint.sub(%r{\A/}, '')}")
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = true

    req = case method.to_s.downcase.to_sym
          when :get
            Net::HTTP::Get.new(uri)
          when :post
            Net::HTTP::Post.new(uri)
          when :put
            Net::HTTP::Put.new(uri)
          when :delete
            Net::HTTP::Delete.new(uri)
          else
            raise ArgumentError, "Unsupported HTTP method: #{method}"
          end

    req['Authorization'] = "Bearer #{@token}"
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    req.body = JSON.generate(body) if body

    response = http.request(req)

    case response.code.to_i
    when 200, 201
      JSON.parse(response.body) rescue {}
    when 204
      {}
    when 401
      raise AuthenticationError, 'Spotify token is invalid or expired (HTTP 401). Please update your SPOTIFY_ACCESS_TOKEN.'
    when 403
      raise ApiError, "Spotify API returned 403 Forbidden. Make sure your token has permissions 'playlist-modify-public' and 'playlist-modify-private'."
    when 429
      retry_after = response['Retry-After']
      raise ApiError, "Spotify rate limit / quota exceeded (HTTP 429#{", retry after #{retry_after}s" if retry_after}). Please provide a fresh SPOTIFY_ACCESS_TOKEN."
    else
      raise ApiError, "Spotify API request failed [#{response.code}]: #{response.body}"
    end
  end
end
