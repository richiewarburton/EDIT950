# AKAI Util 4.6.7 provenance

- Upstream version: 4.6.7
- Publication date: 21 October 2022
- Download URL: https://sourceforge.net/projects/akaiutil/files/akaiutil-4.6.7.tar.gz/download
- Upstream archive SHA-256: `b9b72f7af0a40ec8021bfe23c16bd2c1f17dc80308be5e1249d4d7dac94fdb49`
- Licence: GNU General Public License, version 2 or later (see `gpl-2.0.txt`)

The complete upstream archive is vendored in this directory. Copyright notices
and upstream licence files are preserved.

## Local compatibility change

`commoninclude.h` undefines the modern Apple SDK fortified function-like macros
`bcopy` and `bzero` immediately before AKAI Util's declarations of those
functions. No AKAI filesystem, allocation, filename, sample-conversion, command,
or disk-writing code is changed.

The exact change is also provided as `macos-bcopy-bzero.patch`.
