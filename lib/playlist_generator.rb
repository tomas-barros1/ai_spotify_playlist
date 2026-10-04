# frozen_string_literal: true

require 'ruby_llm'
require 'json'

# Schema defining the structured output expected from Gemini
class PlaylistSchema < Schematist::Schema
  string :name, description: 'Creative and catchy title for the playlist'
  string :description, description: 'Brief and captivating description of the playlist vibe'
  array :tracks, description: 'List of real, existing songs on Spotify' do
    object do
      string :title, description: 'Song title'
      string :artist, description: 'Artist or band name'
    end
  end
end

class PlaylistGenerator
  DEFAULT_MODEL = 'gemini-3.8-flash'

  attr_reader :model

  def initialize(api_key:, model: nil)
    @api_key = api_key&.strip
    raise ArgumentError, 'Gemini API key cannot be blank.' if @api_key.nil? || @api_key.empty?

    @model = (model && !model.strip.empty?) ? model.strip : DEFAULT_MODEL

    RubyLLM.configure do |config|
      config.gemini_api_key = @api_key
      config.default_model = @model
    end
  end

  # Generates a playlist structure (name, description, tracks) based on a prompt
  def generate(prompt, track_count: 10)
    system_instructions = <<~INSTRUCTIONS
      You are an expert music curator, DJ, and Spotify playlist creator.
      Given a user request, generate a cohesive, stylish, and high-quality playlist.
      Select real, well-known, or accurately credited songs that exist on Spotify.
      Include around #{track_count} tracks matching the requested mood, style, genre, or theme.
      Ensure the artist and track title are accurately spelled.
    INSTRUCTIONS

    chat = RubyLLM.chat(model: @model)
                  .with_instructions(system_instructions)
                  .with_schema(PlaylistSchema)

    user_message = "Create a curated Spotify playlist with around #{track_count} songs based on this theme/prompt:\n\"#{prompt}\""
    response = chat.ask(user_message)

    parse_result(response)
  end

  private

  def parse_result(response)
    data = nil
    if response.respond_to?(:parsed) && response.parsed.is_a?(Hash)
      data = response.parsed
    end

    if data.nil? && response.respond_to?(:content) && response.content
      cleaned = response.content.to_s.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
      data = JSON.parse(cleaned) rescue nil
    end

    raise "Failed to parse structured playlist response from Gemini: #{response&.content}" unless data.is_a?(Hash)

    {
      name: data['name'] || 'Curated Playlist',
      description: data['description'] || 'Created with Ruby and Gemini AI',
      tracks: Array(data['tracks']).map do |t|
        {
          title: t['title'] || t[:title],
          artist: t['artist'] || t[:artist]
        }
      end
    }
  end
end
