# Sonora Flutter

Android music-player MVP for an existing self-hosted Sonora Node.js proxy. Flutter handles the interface and native audio playback; the proxy handles YouTube Music, deciphering, BotGuard/WebPO PO tokens, and audio relay.

## Run

Requires Flutter 3.44 / Dart 3.12 or compatible newer versions and the Android SDK.

```sh
flutter pub get
flutter run
```

Open **Settings**, enter your proxy's base URL, check the connection, and save. HTTPS is recommended. No operator endpoint is built into the source. An optional build-time default is supported:

```sh
flutter run --dart-define=SONORA_PROXY_URL=https://your-proxy.example.com
```

This URL is public configuration embedded in the app, not a place for credentials. Use an existing Node proxy with playback support; the source project's experimental Cloudflare adapter is not a full playback backend.

## MVP scope

- Home feed, search with category filters, and album/artist/playlist browsing.
- Real audio through `GET /stream?videoId=...`; no direct Google Video URLs or client-side PO-token generation.
- Mini-player, full player, seek, previous/next, queue selection, and automatic track advance.
- Android media session, background playback service, notification/media-button controls.
- Persisted proxy setting and explicit loading, empty, configuration, network, and playback error states.
- Warm amber Material 3 identity with system light/dark themes.

Account login/library, cookie storage, lyrics, offline downloads, playlist editing, and radio continuation are deliberately outside this MVP. Android is the supported target; generated desktop/iOS projects are not validated release targets.

## Proxy contract

| Endpoint | Usage |
| --- | --- |
| `GET /healthz` | Connection check |
| `GET /home` | Home sections |
| `GET /search?q=...&filter=...` | Search sections |
| `GET /browse?id=...` | Album, artist, playlist sections |
| `GET /stream?videoId=...` | Range-capable audio relay; PO tokens remain server-side |

Feed responses use `{ "sections": [{ "title": "...", "items": [...] }] }`. Playable items supply a `videoId`; browse entries supply `browseId` or `playlistId`. Network failures are not replaced with demo content.

## Check and build

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK: `build/app/outputs/flutter-apk/app-debug.apk`.

UI/emulator testing is deferred at the user's request. HTTP audio relay success and a successful build do not establish audible playback or Android background behavior. Those require a later device run. Release signing remains the generated development configuration; configure your own signing before distribution.

## Layout

- `lib/data/`: proxy models, settings persistence, HTTP client.
- `lib/playback/`: `just_audio` / `audio_service` handler.
- `lib/ui/`: app screens, music lists, player controls.
- `lib/main.dart`: settings and audio-service startup.

Feature development uses isolated `.worktrees/` and separate feature commits. Local worktrees and private environment files are ignored.
