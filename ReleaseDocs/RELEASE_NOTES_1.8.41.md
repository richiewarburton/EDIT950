# EDIT950 1.8.41 (build 62)

EDIT950 1.8.41 removes the brief silent preparation gap when starting P9
audition from the main IMG table.

## Main-table MIDI and keyboard audition

- Prepares each P9's native program data alongside the S9 audition cache when
  an IMG volume opens.
- Makes a newly selected P9 immediately available to **MIDI AUDITION** and
  **COMPUTER MIDI KEYBOARD**, including when those inputs were enabled before
  the program was selected.
- Keeps the existing on-demand preparation as a safe fallback after IMG
  mutations or if an individual P9 could not be cached.
- Leaves Program-editor audition and the shared main-table yellow S9 indicator
  unchanged.

## Validation

- 89 self-contained tests passed with 0 failures.
- The full interaction regression passed and now requires a freshly loaded P9
  to be ready immediately without a wait loop.
- The same regression sends an actual AppKit key event through the focused main
  table, injects external MIDI, renders the sounding S9's yellow table spot and
  verifies independent Note Off handling.
- The optimized app and bundled helper were built and checked as Universal
  `arm64`/`x86_64` binaries with a valid deep ad-hoc signature.
