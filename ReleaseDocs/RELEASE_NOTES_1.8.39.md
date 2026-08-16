# EDIT950 1.8.39 (build 60)

EDIT950 1.8.39 makes the currently open image easier to identify and hardens
both sample and program audition against audio-device changes.

## Finder and image controls

- **Settings → General** can make EDIT950 the Finder default for IMG, P9 and
  S9 files, individually or together. EDIT950 shows a warning before requesting
  the system-wide change.
- Adds an explicit **CLOSE IMG** toolbar button.
- Replaces the generic file total in the browser header with the IMG filename,
  full path, **READ ONLY** or **WRITABLE** state, total file count, P9 count and
  S9 count.

## Audition reliability

- Converts each S9 audition buffer to the active output-device sample rate
  before playback. This fixes valid 44.1 kHz samples being silent when the Mac
  audio output is running at 48 kHz.
- Keeps the currently playing sample alive while a sampling-bandwidth preview
  is rendered, then switches to the completed preview.
- Detects and restarts a stopped P9 audition audio engine when a MIDI or
  computer-key Note On arrives.
- **Panic** now restarts a stopped engine as well as clearing notes.
- Adds program-audition state, input, recovery and failure events to the
  size-limited diagnostic log without recording audio or native file contents.

## Validation

- 89 self-contained tests passed with 0 failures, including Note On and Panic
  recovery from an intentionally stopped program-audition engine and exact
  IMG/P9/S9 document-type declarations.
- The full interaction regression passed, including non-silent rendered audio
  from a 44.1 kHz S9 through a 48 kHz output format, uninterrupted bandwidth
  preview preparation and the detailed IMG header.
- The General Settings visual smoke check passed with the Finder association
  controls visible.
- The browser visual smoke check passed against `beat-disk.img`, showing its
  name, path, read-only state and total/P9/S9 counts.
- The optimized app and bundled helper were built and checked as Universal
  `arm64`/`x86_64` binaries with a valid deep ad-hoc signature.

## Diagnostic finding for `beat-disk.img`

The four `beat-*` S9 files are valid, loud one-shots at 44.1 kHz. `LOOPING.S9`
is a valid alternating-loop sample at 48 kHz. On the reported 48 kHz output
device, only the sample that already matched the hardware rate played. The new
explicit conversion removes that device-rate dependency.
