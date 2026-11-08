# RadioTop

## Workspace boundaries

- Work only inside `/home/mikele/Documents/Proyectos/RadioTop` for this project. Do not inspect or modify sibling projects, other home-directory files, or global configuration.
- Keep generated build output and project tooling state inside this project where the tools allow it.

## Product goal

RadioTop is a Linux desktop internet-radio browser and player built with Dart and Flutter. Its station catalog comes from Radio-Browser (`radio-browser.info`). The interface is information-rich and organized into three main columns: primary navigation, category/search and station results, and the player.

Core requirements:

- Browse and search stations using every taxonomy exposed by Radio-Browser, loading taxonomy values from the API rather than maintaining fixed lists.
- Let the user choose the result count; default to 100.
- Show station favicons and available station metadata in results.
- Persist configuration and favorites under `~/.config/radiotop/` (for example, `config.json` and `favorites.json`).
- Support common internet-radio stream formats through a suitable Linux audio backend.
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
- The default Flutter counter screen is scaffolding and should be replaced as product UI is implemented.

## Working practices

- Preserve user changes and inspect relevant files before editing them.
- Do not add or run tests unless the user asks for testing or verification.
- When reporting work, state what changed and any verification actually performed. Do not claim a build, test, or dependency resolution succeeded unless its command completed successfully.
