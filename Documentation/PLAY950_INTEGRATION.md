# FIND950, EDIT950 and PLAY950

The three applications form a single IMG-library workflow with deliberately
separate product responsibilities.

- [FIND950](https://github.com/richiewarburton/FIND950) indexes
  and searches folders of IMG files, auditions samples read-only, and hands a
  selected image to EDIT950 or a selected program to PLAY950.
- EDIT950 creates and edits IMG, P9 and S9 content, preserves unknown
  native bytes, serializes image mutations and verifies exported results.
- [PLAY950](https://github.com/richiewarburton/PLAY950) is an e45recordings
  macOS VST3 instrument. It loads AKAI content for
  DAW playback, embeds the required program/sample collection for Set recall and
  models the supported S950 playback, filter and envelope behaviour.
- PLAY950 may open an IMG through its read-only AKAI Util extraction workflow,
  but it does not replace EDIT950's editing or image-safety role.

The operational division is: find in FIND950, modify in EDIT950, play and
store with a DAW Set in PLAY950. Original IMG files can remain the archival
source throughout that workflow.

## Shared format evidence

The projects share behavioural and byte-layout evidence rather than a common
source module. Changes to native P9/S9 interpretation should therefore be
checked in both repositories when relevant.

EDIT950 records its P9 evidence in
[`P9_NATIVE_FORMAT.md`](P9_NATIVE_FORMAT.md). Its Diagnostics menu can build a
private playback-validation fixture through production WAV import, P9/S9
modeling, verified IMG writes and native re-export. That fixture remains local;
only generic validation results belong in the public repository.

PLAY950's format documentation is under `docs/`, notably `P9-FORMAT.md`,
`PRODUCT-SCOPE.md` and `RELEASE.md`.

## Cross-project change checklist

When an owned native field, playback rule or fixture changes:

1. Update the format evidence in the project that owns the discovery.
2. Check whether the other project's parser, serializer or playback model uses
   the same assumption.
3. Regenerate the PLAY950 fixture when its specification is affected.
4. Run EDIT950's self-contained and interaction regressions.
5. Run the relevant PLAY950 format, image-workflow and audio tests separately;
   do not modify or discard unrelated work in the companion checkout.
