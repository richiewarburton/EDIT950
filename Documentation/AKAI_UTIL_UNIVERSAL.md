# Universal AKAI Util integration

EDIT950 bundles AKAI Util 4.6.7 as a separately launched Universal
arm64/x86_64 executable in `Contents/Resources/akaiutil`. The application locates
it relative to `Bundle.main`; it contains no developer-machine path and does not
require Rosetta.

The exact modified corresponding source is under `ThirdParty/akaiutil-4.6.7`.
The only compatibility change undefines the modern Apple SDK fortified
`bcopy`/`bzero` macros before the upstream declarations.

## Build and verification

```sh
Scripts/build-release.sh
lipo -archs "Build/EDIT950.app/Contents/Resources/akaiutil"
arch -arm64 "Build/EDIT950.app/Contents/Resources/akaiutil" -h
arch -x86_64 "Build/EDIT950.app/Contents/Resources/akaiutil" -h
codesign --verify --deep --strict --verbose=2 "Build/EDIT950.app"
```

The release script fails if either the app or helper lacks arm64 or x86_64. It
signs the helper first and the outer application last. Its ad-hoc signature is
for development. Public releases must sign the helper with the chosen Developer
ID identity first, sign the completed outer app last, and then notarize the app.

`Scripts/run-akaiutil-equivalence.sh` compares arm64, x86_64 and the trusted
official Intel 4.6.7 binary. It performs read-only `getall`, checks filenames and
SHA-256 for every export, and round-trips every P9 through the app's normal P9
loader.

## Verified private fixtures (9 August 2026)

The equivalence run covered seven privately owned images ranging from small
single-program disks to images containing more than forty programs. All three
executables produced identical filenames and bytes for every fixture. The
genuine-image write runner passed P9 backup, overwrite, forced rollback,
delete/re-import and byte-verification stages on both new slices. The fixtures,
their names and their filesystem locations are not distributed.

## Ten-minute manual acceptance

1. Install the new app on an Apple Silicon Mac and confirm **Open using Rosetta**
   is not selected.
2. Open a disposable copy of a known multi-program IMG and confirm its expected
   programs appear.
3. Inspect several programs and linked samples.
4. Make one harmless edit on a disposable copy, save, close and reopen it.
5. Confirm the edit and all other content remain intact.
6. Open the result in PLAY950 and confirm that it loads and plays.
7. Confirm there was no Rosetta prompt, crash or data corruption.
