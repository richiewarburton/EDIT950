# EDIT950 1.8.44 (build 65)

EDIT950 1.8.44 puts its companion-app handoff controls where the active IMG is
managed.

- **OPEN IN FIND** and **SEND TO PLAY** have been removed from the recent-images
  home screen.
- Both actions now appear in the loaded IMG inspector's Actions section.
- Each action always targets the IMG currently open in EDIT950.

Verification on macOS included the 89-test core suite, the complete interaction
regression, Universal `arm64`/`x86_64` release construction, strict code-signature
verification, and a rendered check of the loaded-IMG inspector.
