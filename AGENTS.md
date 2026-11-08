# RadioTop

## Workspace boundaries

- Work only inside `/home/mikele/Documents/Proyectos/RadioTop` for this project. Do not inspect or modify sibling projects, other home-directory files, or global configuration.
- Keep generated build output and project tooling state inside this project where the tools allow it.

## Product goal

RadioTop is a Linux desktop internet-radio browser and player built with Dart and Flutter. Its station catalog comes from Radio-Browser (`radio-browser.info`). The English-language interface has three columns: navigation and category selectors, a central category picker or station results, and the player.

Core requirements:

- Browse and search by country, genre/tag, and language. Load all available values dynamically from Radio-Browser rather than maintaining fixed taxonomy lists. Do not offer codec as a search filter; codec remains available as station metadata.
- Show the full country list returned by Radio-Browser in the central column, make it searchable, show station counts and country flags, then load that country's stations when selected. Country flags may use a separate ISO metadata source because Radio-Browser's country list does not provide flag codes.
- Show searchable genre and language lists in the central column, then load matching stations when selected.
- Let the user choose the result count; default to 100.
- Show station favicons and available station metadata in results.
- Persist configuration and favorites under `~/.config/radiotop/` (for example, `config.json` and `favorites.json`).
- Support common internet-radio stream formats through a suitable Linux audio backend.
- Keep interrupted streams in play mode and retry automatically at a configurable interval; allow automatic retries to be disabled.
- Make the playback buffer duration configurable and persist playback preferences with the other settings.
- Display all available station and playback information, including current track/artwork when provided and technical stream details such as container, codec, bitrate, bit depth, sample rate, and channel layout when the API, stream, or decoder exposes them. Clearly mark unavailable or unreported values; never invent technical metadata.

## Implementation guidance

- Keep API access, station/domain models, playback integration, persistence, and Flutter presentation in separate, testable units.
- Treat Radio-Browser catalog data and live decoder/stream observations as distinct sources. Preserve the provenance and freshness of technical fields where practical.
- Use stable station UUIDs as identity; do not rely on legacy numeric IDs.
- Send a descriptive application User-Agent to Radio-Browser and follow its documented server-discovery guidance when implementing the client.
- Handle unavailable servers, malformed station data, broken streams, missing favicons, and absent live metadata without losing the rest of the UI.
- Keep Linux support as the target platform; do not add mobile or web platforms unless requested.
- Prefer clear, conventional Dart and Flutter code. Avoid putting API, filesystem, or player logic directly in large widget build methods.

## Project state

- Flutter project package name: `radiotop`.
- Linux desktop scaffolding exists under `linux/`.
- The counter scaffolding has been replaced with the RadioTop catalog browser.
- `run.sh` runs the Linux app through FVM; `compile.sh` creates a Linux release build through FVM.
- Stream playback uses `media_kit` with its Linux MPV backend. Play, pause, stop, live ICY title, buffering state, and decoder details are connected to the UI.
- Settings persist the auto-retry toggle, retry interval, audio buffer duration, and result limit under `~/.config/radiotop/config.json`.
- Radio-Browser requests discover API mirrors and fail over after transient failures.
- The Linux window opens at 1280 × 800 with a minimum size of 1100 × 760.

## Working practices

- Preserve user changes and inspect relevant files before editing them.
- Do not add or run tests unless the user asks for testing or verification.
- When reporting work, state what changed and any verification actually performed. Do not claim a build, test, or dependency resolution succeeded unless its command completed successfully.
