# 🎧 AI Spotify Playlist Generator (Ruby + RubyLLM + Gemini)

A terminal-only Ruby application that transforms any prompt into a curated Spotify playlist using **[RubyLLM](https://rubyllm.com/)** and **Google Gemini**, then automatically creates the playlist and adds the tracks directly to your Spotify account.

---

## 🚀 Features

- **Gemini AI Music Curation**: Uses `ruby_llm` and Gemini (default: `gemini-3.8-flash`) to generate cohesive playlist themes, descriptions, and curated song selections.
- **Structured Schema with Schematist**: Guaranteed JSON schema response containing track titles and artists using `Schematist::Schema`.
- **Spotify Web API Integration**: Accurately searches Spotify for real track URIs (`spotify:track:...`), creates playlists (`POST v1/me/playlists`), and adds items (`POST v1/playlists/{id}/items`).
- **Terminal First**: Run interactively or directly pass arguments in your shell.
- **Token Management**: Easily loads keys from `.env`, with automatic terminal prompting and fallback to `.env`.

---

## 📋 Requirements

- Ruby 3.2+ (tested on Ruby 4.0)
- Bundler
- Google Gemini API key ([Get one free at Google AI Studio](https://aistudio.google.com/))
- Spotify Access Token with `playlist-modify-public` and `playlist-modify-private` permissions ([Get one from Spotify Web API Tutorials/Console](https://developer.spotify.com/documentation/web-api/tutorials/getting-started#request-an-access-token))

---

## 🛠️ Setup

1. **Install gems**:
   ```bash
   bundle install
   ```

2. **Configure environment variables**:
   Create or edit `.env` (a `.env.example` template is provided):
   ```env
   # Google Gemini API Key
   GEMINI_API_KEY=your_gemini_api_key

   # Gemini Model (optional, default: gemini-3.8-flash)
   GEMINI_MODEL=gemini-3.8-flash

   # Spotify User Access Token (from Spotify Web API)
   SPOTIFY_ACCESS_TOKEN=your_spotify_token
   ```

> [!NOTE]
> Spotify access tokens obtained from the Spotify Web API console typically expire in **1 hour**. When expired, simply get a new token from the developer console and update `SPOTIFY_ACCESS_TOKEN` in your `.env`.

---

## 💻 Usage

### 1. Interactive Mode
Run the script without arguments. It will prompt you for your playlist theme/idea:
```bash
bundle exec ruby main.rb
```

### 2. Passing Prompt via CLI Argument
You can pass the prompt directly as a string:
```bash
bundle exec ruby main.rb "90s shoegaze and dream pop"
```

### 3. Customizing Track Count and Privacy
- Specify number of songs (default is 10):
  ```bash
  bundle exec ruby main.rb "upbeat funk and disco for cleaning the house" -n 15
  ```
- Make the playlist public on your profile (default is private):
  ```bash
  bundle exec ruby main.rb "lo-fi hip hop study beats" -p
  ```
- Switch the Gemini model:
  ```bash
  bundle exec ruby main.rb "late night jazz trio" -m gemini-2.5-pro
  ```

---

## 📂 Project Structure

- `main.rb` - CLI entrypoint, argument parsing, terminal output, and orchestrator.
- `lib/playlist_generator.rb` - Configures `RubyLLM` and uses `Schematist::Schema` with Gemini to generate structured track recommendations.
- `lib/spotify_client.rb` - Spotify API client (`search_track`, `create_playlist`, `add_tracks`) based on `main.js`.
- `Gemfile` - Declares `ruby_llm` and `dotenv` dependencies.
- `.env` - Local configuration for API keys.
- `main.js` - Original JavaScript reference script.
