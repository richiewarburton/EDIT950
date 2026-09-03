# EDIT950 1.8.49 (build 72)

EDIT950 1.8.49 adds a direct, branded SAMPLETOOLS sample-editing round-trip and
tidies the selected-sample action panel.

## SAMPLETOOLS round-trip

- Send the selected S9 to installed `com.e45recordings.SAMPLETOOLS` as the same
  private temporary WAV used by EDIT950's external-editor workflow, without
  presenting EDIT950's sample sheet at the same time.
- Put SAMPLETOOLS into contextual Return Mode and use **Return to EDIT950** to
  send the completed output back.
- Bind the return to a unique round-trip directory token rather than the sample
  name or `_OUTPUT.wav` suffix alone.
- Validate the returned WAV before replacing the temporary working copy. A bad
  return leaves the current edit session and source IMG unchanged.
- Present a compact original/returned A/B audition with **Replace Sample**,
  **Save As New**, **Review Settings…** and **Cancel** only after a valid return.
- Keep final IMG mutation explicit so existing backup, capacity, S9 naming,
  P9-reference and byte-verification checks still apply. Review Settings retains
  the complete loop, root-note, compression and bandwidth workflow.

## Inspector actions

- Use the approved SAMPLETOOLS launcher badge in a full-width companion action.
- Align primary, paired secondary, maintenance and destructive actions into a
  clearer compact hierarchy in light and dark appearances.
- Declare WAV as an alternate editable document type so SAMPLETOOLS can return
  its exported output through macOS Launch Services.

## Verification

- All 96 self-contained EDIT950 checks pass.
- The full interaction regression covers the hidden pending state, identified
  return routing, compact comparison, temporary-WAV isolation and cancellation.
- Inspector visual smoke captures pass in light and dark appearances.
