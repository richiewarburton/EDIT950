# EDIT950 — Complete Source

This is the complete buildable source project for EDIT950 1.8.44, build 65.

## Included

- `Sources/EDIT950/` — all application Swift source files and the sanitized Ableton Live 12.4.3 Sampler export template.
- `Tests/` — unit, integration, interaction, genuine-image, Ableton-import, keygroup-transfer and visual regression runners, plus generated-test fixtures.
- `Scripts/` — release, community-package, source-package and regression scripts.
- `Resources/` — the application Info.plist and supplied S950 ICNS artwork.
- `ThirdParty/akaiutil-4.6.7/` — complete corresponding GPL-2.0-or-later
  source, upstream README, provenance, compatibility patch and build guidance
  for the separately launched bundled helper.
- `ReleaseDocs/` — community README and third-party notices.
- `Package.swift`, `README.md`, `LICENSING.md` and `TEST_REPORT.md`.
- `SOURCE_MANIFEST_SHA256.txt` — generated checksums for every packaged source file.

Compiled `.build/` contents, the `Build/` distribution directory, Finder metadata and private user fixtures are deliberately excluded. They are outputs or test inputs, not application source.

The application bundles AKAI Util as a clearly separate executable and includes
its exact corresponding source. EDIT950 does not link to AKAI Util; it launches
the helper as a subprocess. Removable-media metadata cleanup and safe eject are
implemented in EDIT950 with Apple system APIs. Audio samples and disk images are
not bundled. Licensing of the AKAI Util separation should receive human review
before public distribution.

## Requirements

- macOS 14 or later.
- Apple command-line developer tools with Swift.
- Xcode command-line C compiler and `lipo`, used to build the bundled Universal
  AKAI Util 4.6.7 helper.
- Ableton Live 12.4.3 or a compatible later Live 12 release only for opening exported Drum Racks; Ableton is not required to build or run the image-management features.

No third-party Swift package is required.

## Build

From this directory:

```sh
./Scripts/run-tests.sh
./Scripts/build-release.sh
```

The Universal arm64/x86_64 application will be created at:

```text
Build/EDIT950.app
```

The build script signs the completed nested helper first and signs the outer app
last using ad-hoc development signatures. Public distribution must apply the
appropriate Developer ID signature to the helper before signing and notarizing
the outer application.

## Extended regression tests

The standard test suite is self-contained. Extended tests accept external test data and always operate on disposable copies:

```sh
./Scripts/run-integration.sh
./Scripts/run-interaction-regression.sh
./Scripts/run-ableton-import-regression.sh /path/to/rack.adg
./Scripts/run-genuine-image-regression.sh /path/to/source.img
./Scripts/run-keygroup-transfer-regression.sh /path/to/source.img
```

Do not add copyrighted samples, other Ableton presets or personal disk images to the source archive unless you have permission to redistribute them. The included sanitized export template is the only intended ADG resource.
