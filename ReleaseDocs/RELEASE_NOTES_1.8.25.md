# EDIT950 1.8.25 (build 43)

EDIT950 1.8.25 is a workflow, sample-audition, diagnostics and removable-media
safety release. It contains the fixes and enhancements developed after the
1.8.24 GitHub release; the 1.8.24 PolyForm Internal Use licensing terms remain
unchanged.

## A welcoming and dependable launch screen

- Replaced the sparse open screen with a responsive recent-IMG dashboard.
- Added **Load**, **Create Copy and Load**, **Open in FIND**, **Send to PLAY**
  and **Create New** actions.
- **Create Copy and Load** performs a byte-verified copy before opening it, so
  an archival IMG can remain untouched.
- Added double-click loading for recent images.
- Added exactly 200 rotating hints, advanced round-robin on each launch with
  visible previous/next controls.
- Fixed the EDIT950 identity header, logo and tagline so they retain their size
  and remain legible at every Display zoom level.
- Scoped Display zoom to the working browser and launch dashboard rather than
  scaling away the fixed application identity.

## S9 sample editing and audition

- Made Space the default start/stop audition key throughout the sample editor.
- Added a collapsible, two-octave piano keyboard positioned beside Root Pitch.
- The native root note is blue; the note selected for Space has a yellow
  outline and remains explicitly labelled.
- Added **OCT −** and **OCT +** controls and a visible keyboard range.
- Added two keyboard behaviours: click a note to hear it immediately, or select
  a note and trigger it with Space.
- Pitch audition uses sampler-style varispeed, changing pitch and playback speed
  together like the S950 rather than applying a modern duration-preserving
  pitch effect.
- Keyboard pitch combines with Forward/Reverse, One-shot/Loop/Alternating Loop,
  loop points and current sampling-bandwidth preview settings.
- Restyled playback direction, resampling character and playback mode as clear,
  consistent segmented controls.
- Enlarged zero-crossing arrow hit targets to the complete visible buttons and
  kept live loop audition synchronized with manual or arrow-driven changes.
- Long external-editor guidance and replacement messages now wrap instead of
  truncating.
- Fixed a regression where a successful backed-up loop-mode S9 replacement
  could leave the editor sheet open until playback mode was changed to One-shot.

## Removable-media safety across 950TOOLS

- Added a shared cross-process volume-use and eject lease protocol for EDIT950
  and FIND950.
- An IMG kept open from removable media in EDIT950 is treated as active use.
- FIND950 acquires leases only while scanning, audition extraction, exporting
  or handing content to EDIT950; merely browsing its cached catalogue does not
  falsely block an eject.
- Safe Eject acquires the interlock before cleanup inspection or deletion.
- If the companion app is actively using the same volume, eject stops with the
  responsible app and operation named; the volume remains mounted and no
  metadata is removed.
- While Safe Eject is underway, new companion operations on that volume are
  refused, closing the race between the safety check and native macOS eject.
- Stale leases from terminated processes are detected and removed.
- Safe Eject failures now use a dismissible in-app error panel instead of an
  app-modal alert that could leave the application trapped after a permissions
  failure. **OK**, Return and Escape dismiss it; the Full Disk Access shortcut
  dismisses it before opening System Settings.

## User-visible diagnostics

- Added a persistent, rolling diagnostic timeline with bounded disk usage.
- The log records lifecycle, dialogue, helper-command, sample-edit, operation,
  error and Safe Eject events without recording IMG, program, sample or audio
  contents.
- Home and temporary paths are shortened before they enter the readable log.
- Added an in-window viewer plus **Copy**, **Save**, **Reveal** and **Clear**
  controls.
- Added Diagnostics controls in Settings and menu commands to save or reveal
  the live log.
- Errors can automatically expose the diagnostic viewer, making intermittent
  field reports much easier to explain and reproduce.

## Browser and control refinements

- Styled the EDIT950 Inspector visibility control like FIND950, including the
  yellow active-state outline.
- Expanded table interactions to full-cell selection targets and retained stable
  selection through Name, Type and Size sorting.
- Preserved exact native filenames for single and multi-file S9/P9 drag export.
- Continued non-blocking status and header reporting for successful operations.

## Validation

- 73 self-contained EDIT950 tests passed with 0 failures.
- The full interaction regression passed, including live loop and one-shot WAV
  audition, zoom/header behaviour, recent-IMG double-click loading, dismissible
  Safe Eject errors, full-cell selection, backed-up loop-mode replacement
  dismissal, rename, deletion/Undo, exact drag export, Ableton export,
  read-only export and fresh S950 IMG formatting.
- The focused and exact-collection export regression covers source fingerprints,
  collisions, capacity, rollback, exact selection and byte verification.
- A dedicated visual smoke render verified the two-octave keyboard geometry,
  root/Space-note colours, note labels and editor layout.
- The optimized EDIT950 application and bundled AKAI Util helper are Universal
  `arm64`/`x86_64`, ad-hoc signed and verified on disk.

## Licensing and distribution

Current original EDIT950 material remains source-available under PolyForm
Internal Use 1.0.0 with the additional permissions described in `LICENSING.md`.
AKAI Util remains a separate GPL-2.0-or-later executable and its exact
corresponding source is included. This build is ad-hoc signed and is not Apple
notarized.
