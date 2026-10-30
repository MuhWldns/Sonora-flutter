# AGENTS.md — Sonora Flutter

Flutter music-player client for the self-hosted **Sonora Node proxy** ([Sonora-Music](https://github.com/MuhWldns/Sonora-Music)). The app never talks to YouTube/InnerTube directly and holds no secrets — all deciphering/PO-token work happens server-side. The app just calls `/home`, `/search`, `/browse`, `/healthz` and streams from `/stream?videoId=`.

## Commands

```sh
flutter pub get
flutter analyze                          # must stay at 0 issues
flutter test                             # 28 tests; no special flags needed
flutter run [--dart-define=SONORA_PROXY_URL=https://host]   # Android is the primary target
flutter build apk --debug
```

Flutter 3.44+ / Dart ^3.12.2. Windows dev host with cross-drive (C:/D:) layout.

## Architecture & layer rules

```
lib/
├── main.dart        # bootstrap: SettingsStore → SonoraApi → SonoraAudioHandler → LocalDatabase? → SonoraApp
├── data/            # music_models, settings_store, sonora_api, lyrics_store, local_database
├── playback/        # sonora_audio_handler only
└── ui/              # sonora_app, app_scope, root_shell, theme, player_actions,
                     # player/ (controller + chrome), screens/, widgets/
```

- Import direction: `ui` → `data` + `playback`; `playback` → `data`; `data` imports no in-project layer. **`data`/`playback` never import `ui`.**
- `PlayerController` is UI state and lives in `lib/ui/player/player_controller.dart`, not in `playback/`.
- **No state-management package.** Hand-rolled `ChangeNotifier` + `InheritedWidget` (`SonoraScope`) + `ValueNotifier`. Don't introduce Provider/Riverpod/Bloc.
- UI reaches the player only through `PlayerActions.of(context)` (`play`, `playQueue`, `addToQueue`, `open`) and other state via `SonoraScope.of(context)`. Root is an `IndexedStack` of Home/Search/Settings with a persistent `MiniPlayer`.
- `SonoraAudioHandler` serializes queue mutations through a future chain + generation counter (latest request wins); `AudioPlayer.play()` future is never awaited. Preserve this pattern when touching playback.

## Data-layer invariants

- `SettingsStore`: SharedPreferences key `sonora.proxyBase`. "Cleared" state is stored as an **empty string, not key deletion** (deliberate — the `--dart-define=SONORA_PROXY_URL` default must not resurrect). Persist-first: write must succeed before notify.
- `SonoraApi`: injectable `http.Client`; base URL captured synchronously at request start (mid-flight proxy changes don't redirect it); preserves a base path prefix; 20 s timeout; decodes response bodies from UTF-8 **bytes** (latin1 default corrupts text). Error messages are fixed Indonesian strings — never leak server bodies/hosts/URLs into exceptions surfaced to UI.
- `MusicItem`: `isPlayable` requires non-empty `videoId`; `browseTarget` normalizes playlist IDs to canonical `VL…` prefix. Navigation and playback gating both rely on this.
- `LocalDatabase` (3 tables: `playback_history` capped at 100, `favorite_tracks`, `search_history`) is wired into `main.dart` and injected via `SonoraScope.database` as **nullable** — SQLite failure must never be fatal; search history chips and the full-player ♥ degrade gracefully to hidden when null.
- `LyricsRepository` (`lib/data/lyrics_store.dart`) fetches line-synced lyrics from LRCLIB **directly from the client** (no proxy endpoint). Any failure returns `null`, never throws — lyrics are optional. LRC parse: `LyricsRepository.parseSynced`.

## Theme & UI conventions

- Design language: **Nocturne Audio** — dark-first atmospheric with a single crimson accent `kAccent = Color(0xFFE03A3E)` in `lib/ui/theme.dart`; typography **Plus Jakarta Sans** via `google_fonts`. Light mode is a derived derivation; both built by `buildSonoraTheme(Brightness)`, `ThemeMode.system`.
- Surface hierarchy maps to `ColorScheme.surfaceContainer*`: canvas `#0A0F12` (lowest) → base `#0F1417` → containers `#171C1F`/`#1D2327`/`#262D32`/`#353A3D`. Crimson is reserved for focal points (primary CTA, active states, progress) — do not spread it to every icon.
- Non-`ColorScheme` colors go in the `SonoraColors` **ThemeExtension** (accentText, accentHover, onAccent, textTertiary, glassSurface, glassBorder, glow, success); frosted surfaces use the `GlassContainer` helper — no raw hex outside theme.dart (CI sweep: `grep Color(0x` outside theme.dart must stay empty).
- Lyrics view contract: left-aligned, active line = big crimson text **with no card/outline**, blurred artwork backdrop + scrim, per-line fade transition, compact controls raised above the Android gesture bar (`SafeArea` + extra padding).

## Language

- Comments, doc comments, test descriptions, and UI strings are **Indonesian** (README too). Match the surrounding file; `lib/playback/sonora_audio_handler.dart` is the one English-commented file.
- Every file starts with a `library;` directive. Relative imports within `lib/`; `package:sonora_flutter/...` in tests. Single quotes, trailing commas, `const` where possible.
- Commits: Conventional Commits with scopes — `feat(data):`, `fix(playback):`, `build(android):`, `docs:`, imperative, English.

## Tests

- `test/data_test.dart`: `SharedPreferences.setMockInitialValues({})` + `MockClient` from `package:http/testing.dart`; build responses with `http.Response.bytes(utf8.encode(...))`.
- `test/database_test.dart`: `setUpAll(() => sqfliteFfiInit())`, then `LocalDatabase.open(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath)`.
- `test/fixtures/*.json` exist but are currently unreferenced — tests use inline JSON literals.

## Android / build gotchas

- `android/gradle.properties` sets `kotlin.incremental=false` and `kotlin.incremental.jvm=false` — **do not remove**. Kotlin incremental compilation crashes with relative-path errors when project and Gradle cache sit on different Windows drives.
- `AndroidManifest.xml` has `android:usesCleartextTraffic="true"` (plain-http self-hosted proxies must keep working). Permissions: INTERNET, WAKE_LOCK, FOREGROUND_SERVICE(_MEDIA_PLAYBACK). `MainActivity` extends `AudioServiceActivity`.
- `applicationId` is still the template default `com.example.sonora_flutter` (known TODO); release APK currently signs with debug keys.
- Target Android API 21–36+; `docs/` is gitignored (local-only documentation).
