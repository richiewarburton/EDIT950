# EDIT950 1.8.47 (build 68)

EDIT950 1.8.47 fixes bulk P9 edits that appeared to target every keygroup but
were still applied to the previous partial selection.

## Fixed

- Command-A in the P9 editor now runs the editor's explicit
  **Select All Keygroups** action.
- The Select menu and Command-A share the same selection implementation, so the
  selection count beside **Keygroups** and in **Apply to … Keygroups** is the
  actual edit scope.
- Applying Amplitude ENV Release `0` after Select All now changes all 41
  keygroups in the reproduced program rather than only the old partial
  selection.

## Regression coverage

- The rendered test now begins with one selected keygroup instead of being
  preconfigured with all 41 selected.
- It invokes Command-A through the application event path, selects **Set** for
  Amplitude ENV Release, applies zero, encodes the program and reopens it.
- The regression fails unless all 41 decoded Release values are exactly zero.
- The normal suite remains at 90 passing checks, including byte-preserving P9
  serialization and verified IMG overwrite coverage.
