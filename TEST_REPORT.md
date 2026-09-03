# EDIT950 validation report

Current source: **1.8.49 (build 72)**
Platform: macOS 14 or later, Apple silicon and Intel

This report describes the public checks used for EDIT950. Private sampler
images and audio fixtures are never included in the repository; genuine-file
tests accept their inputs explicitly and always work on disposable copies.

## Public checks

Run the self-contained application suite with:

```sh
./Scripts/run-tests.sh
```

The suite covers IMG directory presentation, native P9/S9 handling, WAV
conversion, tags, selection, drag and drop, read-only controls, Ableton
import/export mapping, inter-application requests, removable-media cleanup and
write-verification logic. It includes Save As New selection, temporarily
inverted MIDI key ranges, MIDI running status and parser behaviour, direct P9
keygroup-channel routing, repeated and channel-isolated notes, source-isolated computer
keys, eight-voice stealing, Soft-layer tuning, Constant Pitch, looping,
amplitude/filter envelopes, velocity and keyboard tracking, program teardown,
audio-engine self-recovery on Note On and Panic, byte-preserving keygroup
reordering, bulk-edit model operations, zero-value serialization and
bounded on-screen diagnostic rendering. The P9 coverage includes direct
multi-selection editing, Mixed values, absolute parameter-group paste,
continuous-gesture Undo grouping, recovery journals, source-conflict detection,
atomic staged IMG replacement and the versioned PLAY950 live-audition protocol.
The cross-application coverage validates the branded SAMPLETOOLS launch target,
unique round-trip identifier matching, WAV Launch Services declaration and
validated replacement of only the active sample session's temporary WAV.
It also verifies that bandwidth conversion scales loop endpoints to the
converted WAV's measured frame count, keeps current audition playback alive
until the new preview is ready, and exposes the Finder association controls for
IMG, P9 and S9. The current accepted run completed with **96 passed and 0
failed**, followed by a rendered Mixed-value editor fixture that applies an
absolute Release edit through the real multi-selection control.

The following broader checks are also available:

```sh
./Scripts/run-integration.sh
./Scripts/run-interaction-regression.sh
./Scripts/run-p9-editor-smoke.sh
./Scripts/run-settings-smoke.sh
./Scripts/run-visual-smoke.sh
./Scripts/build-release.sh
```

- The integration check creates a disposable IMG, imports native content,
  exports it again and confirms that the source material remains unchanged.
- The interaction check renders the main application flows and exercises
  selection, editing, rename, import/export and read-only behaviour. It also
  verifies independent external-MIDI/computer-key feedback, three-second trigger
  retention, immediate latest-Note-On movement of the S9 indicator, dropdown-P9
  preparation and routing of both input types to the chosen P9 keygroup channel.
  It requires a P9 from a freshly loaded IMG to be ready immediately, before any
  polling or preparation delay, and sends a real key event through the main
  application window. While that note is held it selects another table row and
  verifies that the dropdown target, voice and feedback remain active.
  The current pass also verifies the open-IMG name, path, access mode and
  total/P9/S9 counts, and proves that a 44.1 kHz S9 renders non-silent audio
  through the current 48 kHz output format. It inspects the actual main-table
  audition cell and requires a rendered yellow triggered-S9 spot. It also
  confirms that the recent-IMG home screen no longer exposes companion-app
  handoff actions. It also creates and byte-verifies a renamed copy of an
  unchanged P9, then deliberately overwrites and verifies that unchanged P9
  without requiring a dummy edit.
- The interaction check proves that sending to SAMPLETOOLS opens no EDIT950
  sample sheet, then sends an identified simulated output back into the compact
  original/returned comparison. It keeps unrelated imports out of that route,
  retains the transfer file, verifies that Cancel leaves the IMG byte-exact,
  and exercises a second return through backed-up, re-exported and verified S9
  replacement.
- The visual checks render the browser, including its persistent IMG-capacity
  header meter and enlarged fixed-region type, plus the sample editor, zoomed
  program editor, settings views and the loaded-IMG inspector for manual
  inspection in light and dark appearances. The inspector check includes the
  **OPEN IN FIND**, **SEND TO PLAY** and branded **EDIT IN SAMPLETOOLS** controls.
- The release build verifies the application metadata, Universal
  `arm64`/`x86_64` architectures and deep ad-hoc signature.

## Genuine-image regression

Optional tests can be run with privately owned S900/S950 images and native
files. Those inputs are supplied at runtime and are not named or bundled in
this repository.

The accepted genuine-image pass covered:

- byte-identical P9 round trips;
- S9 export, edit and replacement with loop and pitch checks;
- verified Save As New creation that preserves the original S9 and P9 bytes;
- verified complete-IMG backups and rollback after injected failures;
- keygroup transfers between writable IMG copies;
- focused export of a P9 and its linked S9 files;
- Ableton Drum Rack import/export mapping; and
- source SHA-256 preservation through every test.

Every mutation is performed on a temporary copy. The original fixture checksum
is recorded before the run and checked again afterwards.

## Safety assertions

Automated and manual checks confirm that:

- read-only mode rejects every mutating command;
- image mutations are serialized;
- replacement content is staged before an IMG is touched;
- successful writes are re-exported and byte-verified;
- Save As New requires a distinct valid S950 name and sufficient additional
  directory and sample-memory capacity;
- Save As New verifies both the new S9 and the unchanged original S9;
- failed verified operations restore the complete backup when available;
- user WAV, P9 and S9 source files are never edited in place;
- temporary audition files are removed with the session; and
- removable-media cleanup matches exact configured names, preserves exceptions,
  refuses unsafe roots, reports partial deletion, and supports a strict
  verification scan before native macOS eject; and
- packaged executables contain no development home-directory paths.

## Release status

The previously reported multi-keygroup editing failure is covered by direct UI,
model, save and reopen regressions in this release.

The local build is ad-hoc signed, not Developer ID signed or notarized. A
packaged public release should be regenerated after source or release-document
changes, then checked on a clean Mac before publication.
