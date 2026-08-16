# EDIT950 1.8.46 (build 67)

EDIT950 1.8.46 fixes the bulk P9 Release edit demonstrated against a real IMG.

## Fixed

- Replaced the fragile SwiftUI optional bulk-operation picker with an explicit
  native **Unchanged / Set / Adjust** control.
- Choosing **Set** now reliably activates the numeric value and enables
  **Apply to Keygroups**.
- Setting Amplitude ENV Release to `0` now changes every selected keygroup and
  survives P9 encoding, IMG overwrite and reopen.

## Regression coverage

- Added a generated 41-keygroup P9 fixture; no private sampler image is bundled.
- The rendered editor test selects all 41 keygroups, chooses **Set** for
  Amplitude ENV Release, applies zero through the editor's default Apply action,
  encodes the result and reopens it.
- The regression fails unless all 41 decoded Release values are exactly zero.
- Existing byte-level bulk-edit, P9 serialization and IMG write-verification
  tests remain in the normal suite.
