# EDIT950 1.8.45 (build 66)

> Superseded test conclusion: subsequent live testing found that bulk edits are
> not reliable for any selection of more than one keygroup. See
> [issue #6](https://github.com/richiewarburton/EDIT950/issues/6).

EDIT950 1.8.45 completes the current audition, IMG-management and P9-editing
work as one release candidate.

## P9 program audition

- Audition a chosen P9 from the main IMG browser using external MIDI or the
  Ableton-style computer keyboard.
- Select the audition P9 independently of ordinary table selection, sorting,
  tagging, dragging and editing.
- Route audition through Omni or a chosen P9 keygroup channel and see held-note
  status plus a yellow spot on the currently triggered Soft S9 row.
- Open the Program editor without losing the main-screen target; closing it
  returns audition to the dropdown program.
- Recover automatically if the audition audio engine stops; Panic also clears
  notes and restores the engine.

## Sample audition and IMG controls

- Play every prepared S9 from its row icon or Space bar, including 44.1 kHz
  samples on a 48 kHz output device.
- Keep the current audition playing while a sampling-bandwidth preview is
  rendered and switched in.
- Associate IMG, P9 and S9 files from Settings after an explicit warning.
- Close the current IMG from the toolbar and identify it by filename, full path,
  writable/read-only state, total files, P9 count and S9 count.
- Open the loaded IMG in FIND950 or send it to PLAY950 from the inspector
  sidebar, where the target is unambiguous.

## Clearer P9 editing and saving

- Bulk numeric fields now have one aligned **Unchanged / Set / Adjust** menu.
  Choosing Set or Adjust activates the row; Unchanged leaves it alone.
- Exact zero-value edits are represented by the bulk editor model, but the live
  multi-keygroup application workflow is not reliable.
- **Save P9 As…** replaces separate filesystem and in-IMG copy buttons, then
  asks whether to save a standalone P9 or a renamed P9 in the current IMG.
- Saving a renamed copy or deliberately overwriting the current P9 remains
  available when no musical values have changed. IMG writes retain the existing
  backup, re-export and byte-verification safeguards.

## Header, help and releases

- Organizes audition controls into Input, Audition Routing, Computer Keys and
  Activity groups with consistently styled dropdowns.
- Replaces rotating launch hints with a direct link to the GitHub User Manual.
- Checks GitHub once per launch and offers a non-modal release-page link when a
  newer version exists. Downloads and installation remain manual.

## Verification

- 90 self-contained tests passed with 0 failures.
- The complete interaction regression passed, including real main-window key
  input, triggered-S9 rendering, output-rate conversion, uninterrupted
  bandwidth preview, IMG identity, companion-action placement and unchanged-P9
  Save As/Overwrite verification.
- Bulk and individual P9 editor smoke renders passed.
- The Universal `arm64`/`x86_64` application and bundled AKAI Util helper were
  built and checked with a strict deep signature verification.
