# frozen_string_literal: true

require 'socket'
require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'timeout'

class SpotifyAuth
  DEFAULT_REDIRECT_URI = 'http://127.0.0.1:8888/callback'
  TOKEN_URL = 'https://accounts.spotify.com/api/token'
  AUTHORIZE_URL = 'https://accounts.spotify.com/authorize'
  SCOPES = %w[
    playlist-modify-public
    playlist-modify-private
    playlist-read-private
    playlist-read-collaborative
  ].join(' ')

  class Error < StandardError; end

  attr_reader :client_id, :client_secret, :refresh_token, :access_token, :expires_at

  def initialize(client_id:, client_secret:, refresh_token: nil, on_token_refresh: nil)
    @client_id = client_id&.strip
    @client_secret = client_secret&.strip
    @refresh_token = refresh_token&.strip
    @on_token_refresh = on_token_refresh

    raise Error, 'SPOTIFY_CLIENT_ID cannot be empty.' if @client_id.nil? || @client_id.empty?
    raise Error, 'SPOTIFY_CLIENT_SECRET cannot be empty.' if @client_secret.nil? || @client_secret.empty?

    @access_token = nil
    @expires_at = nil
  end

  # Returns a valid access token, refreshing or authorizing as needed
  def token
    if @access_token && @expires_at && Time.now < (@expires_at - 60)
      return @access_token
    end

    if @refresh_token && !@refresh_token.empty?
      begin
        refresh_access_token!
        return @access_token
      rescue Error => e
        warn "\n⚠️ Could not refresh token (#{e.message}). Starting browser authorization..."
      end
    end

    authorize!
    @access_token
  end

  # Performs full browser-based OAuth2 Authorization Code flow
  def authorize!(redirect_uri: DEFAULT_REDIRECT_URI)
    uri = URI(redirect_uri)
    port = uri.port || 8888
    path = uri.path.empty? ? '/callback' : uri.path

    auth_params = {
      client_id: @client_id,
      response_type: 'code',
      redirect_uri: redirect_uri,
      scope: SCOPES,
      show_dialog: 'true'
    }
    auth_url = "#{AUTHORIZE_URL}?#{URI.encode_www_form(auth_params)}"

    puts "\n========================================================"
    puts " 🔐 Spotify Authorization Required"
    puts "========================================================"
    puts "Opening your web browser to authorize the application..."
    puts "If the browser doesn't open automatically, visit this URL:\n\n"
    puts "  #{auth_url}\n\n"
    puts "Waiting for authorization on #{redirect_uri}..."
    puts "========================================================"

    # Try to open the browser automatically
    open_browser(auth_url)

    # Listen on local port for callback
    code = capture_authorization_code(port, path)
    raise Error, 'Failed to obtain authorization code from Spotify.' unless code

    puts "✅ Authorization code received. Exchanging for tokens..."
    exchange_code_for_token!(code, redirect_uri)
  end

  # Refreshes the access token using the stored refresh_token
  def refresh_access_token!
    raise Error, 'No refresh token available.' if @refresh_token.nil? || @refresh_token.empty?

    uri = URI(TOKEN_URL)
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Basic #{basic_auth_header}"
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    req.set_form_data(
      'grant_type' => 'refresh_token',
      'refresh_token' => @refresh_token
    )

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    data = JSON.parse(response.body) rescue {}

    if response.code.to_i == 200
      @access_token = data['access_token']
      expires_in = data['expires_in'] || 3600
      @expires_at = Time.now + expires_in

      # Spotify may optionally return a new refresh token (rotation)
      if data['refresh_token'] && data['refresh_token'] != @refresh_token
        @refresh_token = data['refresh_token']
        @on_token_refresh&.call(@refresh_token)
      end

      @access_token
    else
      error_desc = data['error_description'] || data['error'] || response.body
      raise Error, "Failed to refresh Spotify token [#{response.code}]: #{error_desc}"
    end
  end

  private

  def exchange_code_for_token!(code, redirect_uri)
    uri = URI(TOKEN_URL)
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Basic #{basic_auth_header}"
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    req.set_form_data(
      'grant_type' => 'authorization_code',
      'code' => code,
      'redirect_uri' => redirect_uri
    )

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    data = JSON.parse(response.body) rescue {}

    if response.code.to_i == 200
      @access_token = data['access_token']
      @refresh_token = data['refresh_token']
      expires_in = data['expires_in'] || 3600
      @expires_at = Time.now + expires_in

      @on_token_refresh&.call(@refresh_token) if @refresh_token
      @access_token
    else
      error_desc = data['error_description'] || data['error'] || response.body
      raise Error, "Token exchange failed [#{response.code}]: #{error_desc}"
    end
  end

  def capture_authorization_code(port, path)
    server = TCPServer.new('127.0.0.1', port)
    code = nil

    Timeout.timeout(180) do
      client = server.accept
      request_line = client.readline

      # Parse GET request line, e.g. "GET /callback?code=AQ... HTTP/1.1"
      if request_line =~ %r{GET #{Regexp.escape(path)}\?([^\s]+) HTTP}
        query_string = Regexp.last_match(1)
        params = URI.decode_www_form(query_string).to_h
        code = params['code']
        error = params['error']

        if code
          body = <<~HTML
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>Spotify Authorization</title></head>
            <body style="font-family: sans-serif; text-align: center; padding-top: 50px; background: #121212; color: #fff;">
              <h1 style="color: #1DB954;">🎉 Spotify Authorization Successful!</h1>
              <p>You can close this browser tab and return to your terminal.</p>
            </body>
            </html>
          HTML
          client.puts "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
        else
          body = "Authorization failed: #{error || 'Unknown error'}"
          client.puts "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
        end
      else
        body = "Not found"
        client.puts "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      end

      client.close
    end

    code
  rescue Timeout::Error
    raise Error, 'Authorization timed out after 3 minutes. Please try again.'
  ensure
    server&.close rescue nil
  end

  def basic_auth_header
    Base64.strict_encode64("#{@client_id}:#{@client_secret}")
  end

  def open_browser(url)
    if RUBY_PLATFORM =~ /linux/
      system('xdg-open', url, out: File::NULL, err: File::NULL)
    elsif RUBY_PLATFORM =~ /darwin/
      system('open', url, out: File::NULL, err: File::NULL)
    elsif RUBY_PLATFORM =~ /mswin|mingw/
      system('start', url, out: File::NULL, err: File::NULL)
    end
  rescue StandardError
    # Ignore failure to open browser automatically; URL is printed in terminal
  end
end
