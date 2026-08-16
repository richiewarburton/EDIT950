# EDIT950 1.8.47 (build 68)

EDIT950 1.8.47 is the first full GitHub release since 1.8.37. It brings program
audition into the IMG browser, makes sample audition more dependable, identifies
the loaded image clearly and simplifies the routes to documentation, companion
apps and P9 saving.

## Program audition

- Choose the P9 to audition from a dedicated main-screen dropdown that is
  independent of file-table selection.
- Play from external MIDI or the Ableton-style computer keyboard in either the
  browser or Program editor, with Omni or direct P9 keygroup-channel routing.
- See held-note activity and a yellow spot on the Soft-layer S9 most recently
  triggered. The browser target returns after the Program editor closes.
- Prepare P9 and S9 audition data when an IMG opens, and recover the audio engine
  automatically on Note On or with Panic if it stops.

## Sample audition and IMG controls

- Play every prepared S9 from its row icon or the Space bar, including 44.1 kHz
  material through a 48 kHz output device.
- Keep the current audition playing while a sampling-bandwidth preview is
  rendered and switched in.
- Associate IMG, P9 and S9 files with EDIT950 from Settings after an explicit
  warning.
- Close the current IMG from the toolbar and identify it by filename, full path,
  writable/read-only state, total files, P9 count and S9 count.
- Open the loaded IMG in FIND950 or send it to PLAY950 from the inspector
  sidebar; the recent-images screen no longer presents ambiguous handoffs.

## Header, help and releases

- Organizes audition controls into Input, Audition Routing, Computer Keys and
  Activity groups with consistently styled dropdowns.
- Replaces rotating launch hints with a direct link to the GitHub User Manual.
- Checks GitHub once per launch and offers a non-modal release-page link only
  when a newer version exists. Downloads and installation remain manual.

## P9 saving

- **Save P9 As…** chooses between a standalone P9 and a verified renamed P9 in
  the current IMG.
- A renamed copy or deliberate overwrite remains available when no musical
  values have changed. IMG writes retain backup, re-export and byte-verification
  safeguards.
- Command-A and the Select menu use the same explicit Select All Keygroups
  action.

## Known issue

Bulk P9 edits are not reliable when more than one keygroup is selected. This
affects every field and every way of making a multi-keygroup selection; it is
not confined to Release or Select All. Edit one keygroup at a time in this
release and verify the reopened program. Progress is tracked in
[issue #6](https://github.com/richiewarburton/EDIT950/issues/6).

## Verification

- 90 self-contained checks cover the core formats, audition engines, IMG safety
  paths and deterministic P9 model/serialization behaviour.
- The interaction regression covers real main-window keyboard input,
  triggered-S9 rendering, output-rate conversion, uninterrupted bandwidth
  preview, IMG identity, companion-action placement and unchanged-P9 Save
  As/Overwrite verification.
- Current browser and Program-editor renders are included in the release.
- The release build verifies the Universal `arm64`/`x86_64` application,
  bundled AKAI Util helper, metadata and strict deep ad-hoc signature.
