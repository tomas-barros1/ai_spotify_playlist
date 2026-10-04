# 🎧 AI Spotify Playlist Generator (Ruby + RubyLLM + Gemini)

A terminal-only Ruby application that transforms any prompt into a curated Spotify playlist using **[RubyLLM](https://rubyllm.com/)** and **Google Gemini**, then automatically creates the playlist and adds the tracks directly to your Spotify account.

---

## 🚀 Features

- **Gemini AI Music Curation**: Uses `ruby_llm` and Gemini (default: `gemini-3.8-flash`) to generate cohesive playlist themes, descriptions, and curated song selections.
- **Structured Schema with Schematist**: Guaranteed JSON schema response containing track titles and artists using `Schematist::Schema`.
- **Spotify Developer OAuth2**: Full Authorization Code flow with automatic token refresh — no manual copy-pasting tokens ever.
- **Interactive Terminal Menu**: Create new playlists or edit your existing ones (search by name, add/remove tracks, rename).
- **Docker Support**: Run the full app in a container with a single command.

---

## 📋 Requirements

- **Gemini API Key** — [Get one free at Google AI Studio](https://aistudio.google.com/)
- **Spotify Developer App** — [Create free at Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
- Ruby 3.2+ **or** Docker (no Ruby installation needed)

---

## 🛠️ Setup

### 1. Create a Spotify Developer App

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and click **Create app**.
2. Fill in:
   - **App name**: `AI Spotify Playlist`
   - **Redirect URI**: `http://127.0.0.1:8888/callback` *(must match exactly)*
   - **APIs used**: Check **Web API**
3. Click **Save**, then open **Settings** to copy your **Client ID** and **Client Secret**.

### 2. Configure `.env`

Copy the template and fill in your credentials:
```bash
cp .env.example .env
```
```env
GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemini-3.8-flash

SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
```

> [!TIP]
> On first run, the app opens your browser to authorize Spotify. After you approve, a `SPOTIFY_REFRESH_TOKEN` is saved automatically to `.env` — future runs need no browser interaction.

---

## 💻 Running Locally (Ruby)

```bash
bundle install
bundle exec ruby main.rb
```

---

## 🐳 Running with Docker

### Quick start

```bash
# Build and run interactively (first time)
docker compose run --rm --service-ports app
```

> [!IMPORTANT]
> The `--service-ports` flag is required on first login so the Spotify OAuth2 callback (`http://127.0.0.1:8888/callback`) can reach the container from your host browser.
> After the first login the `SPOTIFY_REFRESH_TOKEN` is saved to your `.env` and future runs no longer need a browser.

### Subsequent runs (no OAuth needed)

```bash
docker compose run --rm app
```

### Build only

```bash
docker compose build
```

### Notes

- Port `8888` is mapped from your host to the container for the OAuth2 callback.
- Your `.env` file is **mounted as a volume** so tokens saved by the app are persisted on your host immediately.
- `.env` is **never baked into the image** — secrets stay safe.

---

## 📋 Main Menu

```text
========================================================
 📋 Main Menu
========================================================
  [1] 🎵 Create a new playlist (from Gemini AI prompt)
  [2] ✏️  Edit an existing playlist (show all & search by name)
  [0] 🚪 Exit
```

### Option 1: Create a New Playlist
- Enter your playlist idea/vibe (e.g. `"lo-fi hip hop study beats"`).
- Select track count (default: 10).
- Gemini curates the tracks and title; songs are verified and added to Spotify.

### Option 2: Edit an Existing Playlist
Only shows playlists **you own or can collaborate on**.
- **Search by name**: Type any keyword to filter your playlists instantly.
- **Select & Edit**:
  - `[1] 🤖 Add more tracks with Gemini AI`
  - `[2] ➕ Add a track manually`
  - `[3] 📄 View tracks`
  - `[4] ❌ Remove tracks`
  - `[5] ✏️  Rename / update description`

---

## 📂 Project Structure

```
.
├── main.rb                   # CLI entrypoint and interactive menu
├── lib/
│   ├── spotify_auth.rb       # OAuth2 Authorization Code flow + auto-refresh
│   ├── spotify_client.rb     # Spotify Web API client
│   └── playlist_generator.rb # Gemini AI curation via RubyLLM
├── Gemfile
├── Dockerfile
├── docker-compose.yml
└── .env.example
```
