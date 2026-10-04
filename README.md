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
- Spotify Developer Application ([Create free at Spotify Developer Dashboard](https://developer.spotify.com/dashboard))

---

## 🛠️ Setup

1. **Install gems**:
   ```bash
   bundle install
   ```

2. **Create a Spotify Developer App**:
   - Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and click **Create app**.
   - **App name**: `AI Spotify Playlist`
   - **Redirect URI**: `http://127.0.0.1:8888/callback` *(Crucial: must match exactly)*
   - **APIs used**: Check **Web API**
   - Save and open **Settings** to view your **Client ID** and **Client Secret**.

3. **Configure environment variables in `.env`**:
   ```env
   # Google Gemini API Key
   GEMINI_API_KEY=your_gemini_api_key

   # Gemini Model (optional, default: gemini-3.8-flash)
   GEMINI_MODEL=gemini-3.8-flash

   # Spotify Developer Application Credentials
   SPOTIFY_CLIENT_ID=your_client_id
   SPOTIFY_CLIENT_SECRET=your_client_secret
   ```

> [!TIP]
> **No manual token copying needed!** On first run, the app will open your browser to log in to Spotify once. The app securely saves your `SPOTIFY_REFRESH_TOKEN` in `.env` and automatically refreshes your session in the background forever.

---

## 💻 Usage

Run the terminal application:
```bash
bundle exec ruby main.rb
```

### Main Menu Options:

```text
========================================================
 📋 Main Menu
========================================================
  [1] 🎵 Create a new playlist (from Gemini AI prompt)
  [2] ✏️  Edit an existing playlist (show all & search by name)
  [0] 🚪 Exit
```

#### Option 1: Create a New Playlist
- Enter your playlist idea/vibe (e.g., `"lo-fi hip hop study beats"`).
- Select track count (default: 10).
- Gemini curates the tracks and title using `ruby_llm`.
- Songs are automatically verified and added to your Spotify account.

#### Option 2: Edit an Existing Playlist
- **View all playlists**: Automatically lists all your Spotify playlists with track count and owner.
- **Search by name**: Simply type any keyword (e.g. `funk`, `rock`, `jazz`) to instantly filter your playlists.
- **Select & Edit**: Enter the playlist number to access editing actions:
  - `[1] 🤖 Add more tracks with Gemini AI` (prompt-based addition matching the vibe)
  - `[2] ➕ Add a track manually` (search title/artist)
  - `[3] 📄 View current tracks in this playlist`
  - `[4] ❌ Remove tracks from this playlist`
  - `[5] ✏️  Rename playlist or update description`

---

## 📂 Project Structure

- `main.rb` - CLI entrypoint, argument parsing, terminal output, and orchestrator.
- `lib/playlist_generator.rb` - Configures `RubyLLM` and uses `Schematist::Schema` with Gemini to generate structured track recommendations.
- `lib/spotify_client.rb` - Spotify API client (`search_track`, `create_playlist`, `add_tracks`) based on `main.js`.
- `Gemfile` - Declares `ruby_llm` and `dotenv` dependencies.
- `.env` - Local configuration for API keys.
- `main.js` - Original JavaScript reference script.
