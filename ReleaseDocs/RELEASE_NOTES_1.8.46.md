# EDIT950 1.8.46 (build 67)

> Superseded test conclusion: subsequent live testing found that bulk edits are
> not reliable for any selection of more than one keygroup. See
> [issue #6](https://github.com/richiewarburton/EDIT950/issues/6).

EDIT950 1.8.46 revised the controls used for bulk P9 edits.

## Fixed

- Replaced the fragile SwiftUI optional bulk-operation picker with an explicit
  native **Unchanged / Set / Adjust** control.
- Choosing **Set** now reliably activates the numeric value and enables
  **Apply to Keygroups**.
- The generated editor-model fixture can set and encode Release `0`, but the
  real multi-keygroup workflow remains unreliable.

## Regression coverage

- Added a generated 41-keygroup P9 fixture; no private sampler image is bundled.
- The rendered editor-model fixture starts with all 41 keygroups preselected,
  chooses **Set** for Amplitude ENV Release, applies zero through the default
  Apply action, encodes the result and reopens it.
- The fixture fails unless all 41 decoded Release values are exactly zero. It
  does not reproduce the unreliable live multi-selection path.
- Existing byte-level bulk-edit, P9 serialization and IMG write-verification
  tests remain in the normal suite.
