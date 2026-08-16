# EDIT950 1.8.40 (build 61)

EDIT950 1.8.40 fixes two visible symptoms of one stale main-table cell.

## Sample play buttons

- Each S9 audition cell now observes live application state directly.
- A play button becomes enabled as soon as its asynchronously prepared WAV is
  cached. Earlier builds could leave the first rows looking pale and disabled
  even though Space audition and the underlying cache were ready.
- The table play action continues to use the same verified cached one-shot path;
  the 1.8.39 output-rate conversion and bandwidth-preview behaviour are unchanged.

## Program-audition indication

- The same live cell now renders a 12-point yellow spot with a dark outline on
  the latest Soft-layer S9 triggered by external MIDI or the computer keyboard.
- The spot follows each Note On immediately and remains with the latest trigger
  for the existing three-second feedback interval.

## Validation

- 89 self-contained tests passed with 0 failures.
- The full interaction regression passed and now inspects the actual table cell,
  requiring yellow pixels to render on the triggered S9 row.
- BEAT-DISK visual validation showed enabled play icons for `beat-01` through
  `beat-04`, `LOOPING` and `LOOPING 2`.
- HARDBREAK visual validation showed enabled play icons for all 13 S9 samples.
- Sampling-bandwidth audition continuity remained green in the interaction run.
- The optimized application and bundled AKAI Util helper were verified as
  Universal `arm64`/`x86_64` binaries with a valid deep ad-hoc signature.
