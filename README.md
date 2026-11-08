# RadioTop

RadioTop is a Linux desktop internet-radio browser built with Flutter. It uses the
Radio-Browser community catalog to search stations and load available countries,
genres, and languages at runtime.

## Current state

- Three-column desktop layout with navigation, searchable country/genre/language
  selectors, station results, and a station information panel.
- Station search with a configurable result count (100 by default).
- Station artwork and catalog metadata, with explicit “Not reported” values for
  technical details not provided by the catalog.
- Favorites and the selected result count saved under `~/.config/radiotop/`.
- Stream playback is not implemented yet.

## Run

Use a Flutter SDK with Linux desktop support enabled, then run:

```sh
fvm flutter run -d linux
```

Radio-Browser may be unavailable temporarily; the app reports connection errors
and allows retrying without losing the rest of the interface.
