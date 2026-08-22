# EDIT950 1.8.48 (build 69)

EDIT950 1.8.48 overhauls P9 keygroup editing, makes unsaved work recoverable,
strengthens IMG write safety and adds private live audition with PLAY950.

## Direct multi-keygroup editing

- Select keygroups with click, Command-click, Shift-click or Command-A while
  retaining a clear primary keygroup.
- Show **Mixed** when selected keygroups differ and apply an entered, dragged,
  stepped or chosen value absolutely to the complete selection.
- Commit typed values with Return or focus change, cancel with Escape, use
  arrows for normal increments, Shift for fine dragging and Option for coarse
  changes.
- Treat one drag as one Undo step. Selection changes do not pollute Undo history.
- Duplicate selected keygroups as one ordered block, reorder complete records,
  and copy or paste whole keygroups and named parameter groups.
- Preserve unknown P9 bytes and sampler-maintained structural boundaries.

This resolves [issue #6](https://github.com/richiewarburton/EDIT950/issues/6).

## Save, Undo and recovery

- Keep P9 edits in memory until explicit Save or Command-S.
- Retain Undo history across Save and track the clean marker through Undo/Redo.
- Detect external changes to standalone P9 and IMG-backed source programs.
- Journal unsaved work against the exact source and baseline, then offer
  recovery after interruption. Close Without Saving removes the journal.
- Stage an IMG copy, mutate and re-export only the staged P9, byte-verify it,
  re-check the source IMG checksum and atomically replace the source only after
  every check passes.

## PLAY950 live audition

- Accept a short-lived, versioned request containing the exact P9 selected in
  PLAY950, its IMG path, baseline and private plug-in instance identifier.
- Stream throttled, validated P9-only revisions to that PLAY950 instance while
  the IMG remains unchanged until Save.
- Report Syncing, Auditioned, Sync Error and PLAY Disconnected states and resend
  the latest valid snapshot after reconnection.

PLAY950 currently needs **Reload Source** before a later editing session can use
the newly saved IMG as its baseline. Automatic rebase is tracked in
[PLAY950 issue #5](https://github.com/richiewarburton/PLAY950/issues/5); Reload
Source remains useful for external changes and full-source recovery.

## Verification

- All 96 self-contained EDIT950 checks pass.
- The full interaction regression passes, including direct save/reopen,
  continuous Undo grouping, retained Undo history, atomic failure recovery and
  immediate recovery-journal discard.
- A 99-keygroup absolute edit and serialization completes within the 100 ms
  acceptance boundary.
- A real PLAY950 editor-host session opened the exact P9, rejected an invalid
  revision, recovered to Auditioned on a valid six-keygroup edit and left the
  source IMG byte-identical until Save.
- The Universal `arm64`/`x86_64` app and bundled AKAI Util helper pass metadata,
  resource and strict deep code-signature verification.
