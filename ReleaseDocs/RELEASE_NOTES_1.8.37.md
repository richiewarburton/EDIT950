# EDIT950 1.8.37 (build 55)

EDIT950 1.8.37 contains the workflow, audition, diagnostics, appearance and
removable-media changes developed after the 1.8.24 GitHub release.

## Launch and main browser

- Added a recent-IMG launch screen with **Load**, **Create Copy and Load**,
  **Open in FIND**, **Send to PLAY** and **Create New** actions.
- **Create Copy and Load** byte-verifies the copy before opening it.
- Added double-click loading and 200 rotating workflow hints.
- Kept the EDIT950 identity header fixed while Display zoom applies to the
  launch screen and working views.
- Added a persistent IMG-capacity header with used space, free space, percentage
  and a blue/yellow/red meter.
- Added System, Light and Dark appearance choices in Settings and the View menu.
- Expanded table interactions to full-cell selection targets and retained
  selection through Name, Type and Size sorting.
- Preserved exact native filenames for single and multi-file S9/P9 drag export.
- Registered S9 imports separately from P9 and IMG documents and kept ISO disk
  images at alternate-handler rank rather than claiming them as EDIT950 files.

## S9 sample editing and audition

- Made Space the default start/stop audition key throughout the sample editor.
- Added a collapsible two-octave keyboard with a blue root note, a yellow
  audition-note marker, octave controls and a visible keyboard range.
- Added immediate click audition and selected-note audition modes.
- Added optional input-only MIDI audition with Omni or channel filtering, note
  priority, running-status handling and a Panic control.
- Kept pitch audition sampler-style: pitch and playback speed change together.
- Combined keyboard or MIDI pitch with direction, playback mode, loop points and
  sampling-bandwidth preview settings.
- Added **Save As New** for a distinct S9. It checks directory and memory
  capacity, verifies the new S9 byte-for-byte and verifies that the original S9
  and P9 references remain unchanged.
- Restyled playback direction, resampling character and playback mode as
  consistent segmented controls.
- Enlarged zero-crossing arrow hit targets to the complete visible buttons.
- Kept loop audition synchronized with manual and arrow-driven changes.
- Scaled loop endpoints to the converted WAV's measured frame count while
  sampling bandwidth is adjusted during audition.
- Wrapped external-editor and replacement guidance rather than truncating it.
- Fixed the editor remaining open after a verified backed-up loop-mode replace.

## P9 editing

- Applied Display zoom to the P9 keygroup editor.
- Added complete keygroup-row reordering while preserving musical fields,
  unknown bytes and documented structural rules.
- Kept range display and selection valid for temporarily inverted MIDI ranges.

## Diagnostics and removable-media safety

- Added a persistent rolling diagnostic timeline with bounded disk use.
- The log records lifecycle, dialogue, helper-command, sample-edit, operation,
  error and Safe Eject events without recording IMG, P9, S9 or audio contents.
- Shortened home and temporary paths in the readable log.
- Added an in-window viewer with **Copy**, **Save**, **Reveal** and **Clear**.
- Added a shared EDIT950/FIND950 removable-volume lease protocol.
- Safe Eject stops before cleanup when either application is actively using the
  same volume and names the application and operation responsible.
- An eject lease prevents new companion work on the volume until native macOS
  eject succeeds or is cancelled.
- Stale leases from terminated processes are removed.
- Safe Eject failures use a dismissible in-app error panel.
- Fixed recent IMG loading and Safe Eject error dismissal regressions found
  during release staging.

## Validation

- 80 self-contained EDIT950 tests passed with 0 failures.
- The full interaction regression passed, including browser capacity display,
  sample audition, bandwidth conversion, Save As New, verified replacement,
  P9 editing, recent-IMG loading, Safe Eject errors, selection, drag export,
  Ableton export, read-only export and fresh IMG formatting.
- Visual smoke renders covered the browser, S9 editor, bandwidth page,
  diagnostic viewer, P9 editor and Settings in light and dark appearances.
- The optimized EDIT950 application and bundled AKAI Util helper are Universal
  `arm64`/`x86_64`, ad-hoc signed and verified on disk.

## Licensing and distribution

Current original EDIT950 material remains source-available under PolyForm
Internal Use 1.0.0 with the additional permissions described in `LICENSING.md`.
AKAI Util remains a separate GPL-2.0-or-later executable and its exact
corresponding source is included. This build is ad-hoc signed and is not Apple
notarized.
