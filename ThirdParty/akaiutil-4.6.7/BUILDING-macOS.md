# Building the bundled macOS helper

From the EDIT950 source root run:

```sh
Scripts/build-akaiutil-universal.sh /tmp/akaiutil
lipo -archs /tmp/akaiutil
arch -arm64 /tmp/akaiutil -h
arch -x86_64 /tmp/akaiutil -h
```

The script uses the active Xcode command-line tools, targets macOS 14, compiles
separate arm64 and x86_64 executables from this directory, combines them into a
Universal Mach-O executable, and fails unless both architectures are present.

For distribution, sign the helper with the intended Developer ID identity before
signing the outer application. Submit the fully signed outer application for
notarization. The local release script uses ad-hoc signing for development builds.
