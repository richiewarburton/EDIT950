# EDIT950 1.8.38 (build 59)

EDIT950 1.8.38 adds playable P9 program audition to the main IMG browser and
program editor without changing native P9 or S9 content.

## Program audition

- Plays the Soft sample layer only, with eight voices and deterministic oldest
  voice stealing matched to PLAY950.
- Applies P9 Soft tuning, Constant Pitch, velocity-to-loudness, amplitude ADSR,
  Soft filter, filter ADSR/amount, velocity-to-filter and keyboard-to-filter.
- Applies native S9 one-shot, forward/reverse loop and alternating-loop rules.
- One-shot voices ignore Note Off; other voices enter amplitude release.
- Stops and clears safely when monitoring is disabled, the editor closes, the
  selected program changes or prepared sample data is invalidated.

## Inputs and feedback

- Adds explicit, shared **MIDI AUDITION** and **COMPUTER MIDI KEYBOARD** toggles
  to the main screen and P9 editor.
- Supports Omni or direct P9 keygroup channels 1–16. Choosing a channel routes
  both physical MIDI and computer-key notes to keygroups programmed for that
  displayed channel, while retaining the physical input channel for Note Off.
- Matches Ableton Live's computer-key map: A–L and the black-key row play notes,
  Z/X select octave and C/V select velocity.
- Shows held MIDI and computer keys live, including source, physical key, note,
  channel, velocity and no-match state. The latest trigger remains visible for
  three seconds unless another note is played.
- Highlights matching program keygroups and moves the main-table dot immediately
  to the Soft S9 mapped to each newest Note On. The dot then remains for the
  three-second feedback window.
- Prepares the selected main-table P9 when audition input is enabled, names the
  target during preparation and readiness, and does not re-export it when the
  channel or second input toggle changes.
- Distinguishes **NO KG MATCH** from **NO PLAYABLE SOFT S9**, and reports the
  number of playable Soft keygroups for the selected target/channel.
- Enlarges the fixed header, audition strip, inspector and bottom status text so
  these areas remain legible beside a zoomed file table.
- Keeps repeated notes, input sources and MIDI channels independently ordered so
  each Note Off releases only its intended voice.

## Validation

- 88 self-contained tests passed with 0 failures.
- The full interaction regression passed, including rendered dual-source key
  feedback and triggered-sample dots in the main table.
- The P9 editor visual smoke check passed with the shared controls visible.
- The optimized app and bundled helper were built and checked as Universal
  `arm64`/`x86_64` binaries with a valid deep ad-hoc signature.

## Intentional limits

Program audition does not play the Loud layer and does not implement pitch bend,
modulation, aftertouch, sustain pedal or S950 multi-output routing. Its channel
selector directly targets a P9 keygroup channel for diagnosis; PLAY950's DAW
Basic Channel plus keygroup-offset routing remains a separate playback feature.
