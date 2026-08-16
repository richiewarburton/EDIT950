# EDIT950 1.8.43 (build 64)

EDIT950 1.8.43 completes the main-screen audition controls and makes help and
new releases easier to find.

- The audition strip is organized into Input, Audition Routing, Computer Keys
  and Activity groups.
- The P9 target and keygroup-channel dropdowns use the same compact visual
  treatment, with no duplicate system menu indicators.
- P9 audition selection remains independent of ordinary file-table selection.
- The 200 rotating launch-screen hints and their stored state have been removed.
- The launch screen now provides one explicit link to the GitHub User Manual.
- EDIT950 checks GitHub once per launch. A newer release appears as a
  dismissible, non-modal notice linking to its release page.
- **EDIT950 → Check for Updates…** reports the installed and latest versions on
  demand. Downloads and installation remain manual.

Verification on macOS included the 89-test core suite, the complete interaction
regression, Universal `arm64`/`x86_64` release construction, strict code-signature
verification, and rendered checks of the main audition strip, launch-screen
manual link and update-result sheet.
