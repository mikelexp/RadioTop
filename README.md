# RadioTop

RadioTop is a Linux desktop internet-radio browser and player built with Flutter.
It uses the Radio-Browser community catalog to search stations and load its
countries, genres, and languages at runtime. The app interface is in English.

## Current state

- Three-column desktop layout with navigation and category selectors, a central
  searchable country/genre/language picker and station list, and a player panel.
- Country entries show flags and the number of stations in the Radio-Browser
  catalog. Selecting a country, genre, or language loads matching stations.
- Station search with a configurable result count (100 by default).
- Station artwork and catalog metadata, with explicit “Not reported” values for
  technical details not provided by the catalog.
- Stream playback through `media_kit` and its Linux MPV backend, including play,
  pause, stop, live ICY titles, buffering state, and available decoder details.
- Automatic stream reconnection, enabled by default with a five-second interval.
  It can be disabled or configured in Settings. The audio buffer is also
  configurable from 1 to 30 seconds.
- Favorites, result count, retry preferences, and buffer duration saved under
  `~/.config/radiotop/`.
- Codec is shown as station metadata but is not a search filter.
- Radio-Browser mirror discovery and failover on transient request failures.
- The Linux window opens at 1280 × 800 and cannot be resized below 1100 × 760.

## Run and build

Run the app with FVM and the Linux desktop target:

```sh
./run.sh
```

Create a Linux release build:

```sh
./compile.sh
```

The release bundle is written under `build/linux/<architecture>/release/bundle/`.
Both scripts accept additional Flutter command-line arguments.

Radio-Browser may be unavailable temporarily. The app discovers available API
mirrors, tries another mirror when a transient request fails, and reports an
error with a manual retry option if they are all unavailable.
