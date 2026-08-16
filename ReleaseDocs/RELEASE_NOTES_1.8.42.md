# EDIT950 1.8.42 (build 63)

EDIT950 1.8.42 separates the main-screen P9 audition target from ordinary file
selection.

## Audition program dropdown

- Adds a labelled **AUDITION PROGRAM** dropdown containing every P9 in the open
  S950 volume.
- Keeps the chosen audition program independent of table selection, sorting,
  tagging, editing, dragging and export operations.
- Changing table rows no longer panics or releases currently held program
  audition notes.
- Selecting a dropdown program uses the P9 data prepared during IMG opening, so
  MIDI and computer-keyboard audition remains immediate.
- Opening the Program editor temporarily auditions its in-memory program;
  closing it returns to the main dropdown choice.
- Clears the dropdown safely when its IMG or volume closes, changes, or no
  longer contains the chosen P9.

## Validation

- 89 self-contained tests passed with 0 failures.
- The full interaction regression passed with a rendered `SELECT P9` menu.
- The regression chooses the program through the new model control, sends an
  actual main-window key event, changes to a different table row while that note
  is held, and verifies the target, voice and yellow S9 feedback remain active.
- A 1180×760 light-mode smoke render confirms that the labelled menu fits the
  fixed audition strip without crowding adjacent controls.
- The optimized app and bundled helper were built and checked as Universal
  `arm64`/`x86_64` binaries with a valid deep ad-hoc signature.
