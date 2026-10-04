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
    when 401
      raise AuthenticationError, 'Spotify token is invalid or expired (HTTP 401). Please update your SPOTIFY_ACCESS_TOKEN.'
    when 403
      raise ApiError, "Spotify API returned 403 Forbidden. Make sure your token has permissions 'playlist-modify-public' and 'playlist-modify-private'."
    else
      raise ApiError, "Spotify API request failed [#{response.code}]: #{response.body}"
    end
  end
end
