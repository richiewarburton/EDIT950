# EDIT950 validation report

Current source: **1.8.25 (build 43)**
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
write-verification logic. The current accepted run completed with **73 passed
and 0 failed**.

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
  selection, editing, rename, import/export and read-only behaviour.
- The visual checks render the browser, editor and settings views for manual
  inspection.
- The release build verifies the application metadata, Universal
  `arm64`/`x86_64` architectures and deep ad-hoc signature.

## Genuine-image regression

Optional tests can be run with privately owned S900/S950 images and native
files. Those inputs are supplied at runtime and are not named or bundled in
this repository.

The accepted genuine-image pass covered:

- byte-identical P9 round trips;
- S9 export, edit and replacement with loop and pitch checks;
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
- failed verified operations restore the complete backup when available;
- user WAV, P9 and S9 source files are never edited in place;
- temporary audition files are removed with the session; and
- removable-media cleanup matches exact configured names, preserves exceptions,
  refuses unsafe roots, reports partial deletion, and supports a strict
  verification scan before native macOS eject; and
- packaged executables contain no development home-directory paths.

## Release status

The local build is ad-hoc signed, not Developer ID signed or notarized. A
packaged public release should be regenerated after source or release-document
changes, then checked on a clean Mac before publication.
