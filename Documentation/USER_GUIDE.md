# EDIT950 musician’s guide

EDIT950 is for opening, auditioning and changing S900 and S950 disk images on a
Mac. It is built around a simple rule: let you work creatively, but make risky
changes obvious and check the result afterwards.

This guide assumes macOS 14 or later.

## Three old sampler terms you will see

| Label | What it means to a musician |
| --- | --- |
| **IMG** | A copy of a complete sampler disk. |
| **P9 program** | The playable instrument: keyboard zones, tuning, layers, envelopes and outputs. |
| **S9 sample** | One recording used by a program. |

## Install and open your first disk

1. If you have a packaged **EDIT950.app**, move it to `/Applications`. The
   [EDIT950 project page](https://github.com/richiewarburton/EDIT950) shows the
   current download and source-build status.
2. Open the app. If macOS blocks the first launch, Control-click the app, choose
   **Open**, then confirm.
3. The launch screen lists recent IMGs. Use **Load** to reopen one, or **Create
   Copy and Load** to make a byte-verified working copy first. **Create New** is
   available from the same screen. After an IMG is loaded, use **Open in FIND**
   or **Send to PLAY** in its inspector sidebar; those actions always target the
   currently loaded image.
4. You can also drag an `.img` file onto the window or choose **Open Image**.
5. For an irreplaceable archive, leave **Open read-only** switched on at first.

AKAI Util 4.6.7 is included with EDIT950. No separate download, path selection,
`chmod` command or other Terminal setup is required. EDIT950 uses it for the
underlying IMG filesystem operations. Safe Eject is separate native EDIT950
code.

![EDIT950 browsing samples and programs on an IMG](Images/edit950-browser.png)

Samples and programs have different colours and icons. The blue play button
auditions a sample. At the right of the header, EDIT950 shows the open IMG's
name and full path, whether it is **READ ONLY** or **WRITABLE**, and separate
totals for all files, P9 programs and S9 samples. The persistent meter beside
it shows used space, free space and the percentage occupied.

Use the explicit **CLOSE IMG** toolbar button when you want to return to the
launch screen without quitting EDIT950.

When an IMG opens, each S9 play button becomes active as soon as its audition
copy is ready. A temporarily pale button is still being prepared.

The lock at the bottom means the IMG is open read-only. You can listen and
inspect safely, but EDIT950 will not offer actions that change the disk.

## Keyboard shortcuts

These shortcuts cover the jobs you are most likely to do repeatedly. The app’s
menus show them too.

| Shortcut | What it does |
| --- | --- |
| **Space** | Audition the selected sample. Press it again to stop. |
| **Command-O** | Open an IMG disk. |
| **Shift-Command-O** | Open a loose P9 program. |
| **Command-N** | Create or format an IMG. |
| **Command-W** | Close the current IMG. |
| **Command-I** | Import WAV files. |
| **Command-E** | Export the selected samples or programs. |
| **Option-Command-E** | Copy the selected original S9 or P9 files. |
| **Option-Command-P** | Edit the selected P9 program. |
| **Command-R** | Refresh the open disk. |
| **Delete** | Ask to delete the selected items from a writable IMG. |
| **Command-minus** | Make the EDIT950 display smaller. |
| **Command-0** | Return the display to its normal size. |
| **Command-plus** | Make the EDIT950 display larger. |
| **Command-Z** | Undo the last supported change. |
| **Shift-Command-Z** | Redo the change. |

Space works when the file list is active and one sample is selected. Delete
still shows a confirmation before changing the IMG.

## Hear what is on the disk

Click the blue play button beside an S9 sample. Click it again to stop.

Double-click the sample, or open its action menu, to see more detail. From the
sample editor you can:

- audition the sound;
- export it as a WAV;
- inspect pitch, loops and playback direction;
- adjust the musical root note;
- change loop and playback behaviour; and
- reduce bandwidth for a smaller, rougher, more obviously S950-flavoured sound.

![S9 playback, loop and MIDI audition controls](Images/edit950-sample-editor.png)

Expand **Keyboard** for a two-octave playing surface. The native root note is
blue and the note assigned to Space has a yellow marker. **Click plays note**
auditions directly from the keyboard; **Audition uses note** selects the pitch
used by the main Audition button and Space. The result uses sampler-style
varispeed, so pitch and playback speed change together.

**MIDI Audition** is optional and input-only. Choose a MIDI channel or Omni,
then play a connected controller. EDIT950 neither sends MIDI nor changes the
source sample. **Panic** clears held-note state if a controller connection is
interrupted.

Bandwidth is best treated by ear. Lower settings use less sampler memory and
lose more top end; the raw mode can add deliberate grit and aliasing. Prepare
and audition the preview before saving. Loop endpoints are scaled to the actual
converted WAV frame count while the preview sample rate is being changed. If a
sample is already playing, it continues until the converted preview is ready.

![S950 sampling bandwidth and projected IMG use](Images/edit950-bandwidth-editor.png)

The bandwidth page shows the projected sample size and IMG capacity before the
final save. Its Clean mode filters frequencies that cannot survive the lower
rate; Raw keeps the unfiltered conversion character.

At the final step, choose **Save As New** to add a separately named S9 or
**Replace** to update the existing one. Save As New checks directory entries and
sample memory, re-exports the new S9 for byte comparison, and verifies that the
original S9 and its P9 references are unchanged. Both actions offer a complete,
verified IMG backup before writing.

## Understand a program without becoming a technician

Double-click a red P9 program to open the program editor.

![The P9 editor showing one keyboard zone and its musical controls](Images/edit950-p9-editor.png)

A **keygroup** is simply a keyboard zone. Select one on the left, then work from
the musical questions on the right:

- Which keys should play this zone?
- Which sample should it use?
- Should a harder note switch to a second sample?
- Is the sample too loud, dull, bright, sharp or flat?
- Should it play once or stop when the note ends?
- Which output should it use?
- How fast should the sound start, fall away and release?

The **Soft Sample** is the normal or lower-velocity sound. Expand **Loud Sample**
when the program uses a second layer for harder playing.

Use the same audition strip above the main IMG table or inside the P9 editor:

- **MIDI AUDITION** listens to a connected controller.
- **COMPUTER MIDI KEYBOARD** turns the Mac keyboard into note input.
- **Omni** ignores each keygroup's MIDI-channel field. Choosing **KG CH 1–16**
  auditions keygroups programmed for that displayed P9 channel. Both a physical
  MIDI controller and the computer keyboard are routed to the chosen channel.
- **Panic** releases and safely clears all active notes. If the audition audio
  engine has stopped, Panic restarts it too.

The computer layout matches Ableton Live. A, W, S, E, D, F, T, G, Y, H, U, J,
K, O, L and P play consecutive notes from C; Z/X lower or raise the octave and
C/V lower or raise velocity. These keys are ignored while typing in a text
field.

Choose the main-screen P9 from **AUDITION PROGRAM**. This dropdown is independent
of table selection, so you can browse, tag, edit or export other rows without
changing the program being played or stopping its held notes. P9 data is
prepared when the IMG opens, so MIDI and computer-key notes can play the chosen
program immediately. The strip names the target and includes how many Soft-layer
keygroups are playable on the chosen channel. Changing the audition channel does
not repeatedly export the program.

Opening the P9 editor temporarily makes that editor's program the audition
target. Closing the editor returns audition to the program chosen in the main
dropdown.

Held notes appear in the strip with **MIDI** or **KEYBOARD**, the physical key
where applicable, note, MIDI number, physical input channel, routed P9 channel
and velocity. **NO KG MATCH** means the audition P9 has no keygroup for that
note/channel. **NO PLAYABLE SOFT S9** means the keygroup exists but its Soft
sample is blank, missing or unavailable. Matching keygroups highlight in the
editor, and the latest triggered Soft-layer S9 gains a yellow spot in the main
table. The spot jumps to the newly mapped S9 as soon as each MIDI or Mac-keyboard
Note On is received. The latest note and S9 spot then remain visible for three seconds;
playing another note immediately starts a new indication. In non-Omni mode, the
physical controller channel is shown but does not prevent audition: the note is
routed to the chosen P9 keygroup channel. The two input sources remain separately
visible and release independently even when they play the same MIDI note.

This selector is deliberately an EDIT950 audition channel, not PLAY950's Basic
MIDI Channel control. PLAY950 still applies its Basic Channel plus P9 offset when
used in a DAW; EDIT950 selects the P9 channel directly so channel programming can
be checked without first reconfiguring the controller.

P9 audition uses up to eight voices and the program's Soft-layer tuning,
Constant Pitch, one-shot/loop direction, amplitude envelope and filter settings.
The Loud layer and MIDI controllers are not auditioned. **MIDI AUDITION** is
input-only: EDIT950 never sends MIDI or changes the source program.

Display zoom applies to the P9 editor as well as the main browser. Keygroup rows
show their musical and MIDI ranges and can be dragged to reorder complete
keygroup records without rebuilding their musical settings.

Use **Save P9 As…** to choose between a standalone P9 file and a new, renamed
P9 beside the current program in the open IMG. **Overwrite in IMG…** replaces
the current P9 after the usual backup choice and byte verification. Both IMG
actions remain available even when the program is unchanged, which is useful
for making a verified duplicate or deliberately rewriting a suspect directory
entry.

## Editing more than one keygroup

The program editor displays bulk Set/Adjust controls when more than one
keygroup is selected. In 1.8.47, applying those controls is not reliable for
any selection of more than one keygroup. The limitation is not confined to the
Release field or to Select All.

Until [issue #6](https://github.com/richiewarburton/EDIT950/issues/6) is resolved,
edit one keygroup at a time and verify the saved program after reopening it.
Do not rely on **Apply to Keygroups** for a multi-keygroup selection in this
release.

The visual controls remain present so the affected workflow can be diagnosed;
their presence is not a guarantee that every selected keygroup will change.

## Import and export WAV files

### Export a sample

Select one or more S9 samples and choose **Export**. Normal WAV exports keep
valid loop markers, so another music application can see where the loop starts
and ends.

### Import a WAV

Open a writable IMG, choose **Import**, then select a mono PCM WAV. EDIT950 shows
the proposed sampler name and estimated space before writing.

Short names are normal on old samplers. Choose something you will still
recognise on the S950 screen.

### Replace a sample carefully

When replacing a sample that programs already use, keep the sampler-visible
name the same unless you also want to update those program links. EDIT950 can
update matching references when you intentionally rename a sample.

## Create a fresh working disk

Choose **New Image** when you want a clean 800 KB or 1.6 MB IMG. A fresh image is
useful for:

- a focused live set;
- one song’s drum kit;
- a deliberately small sound palette;
- a Gotek or real S950; or
- a tidy source for PLAY950.

Import samples first, then create or import the P9 programs that use them. Keep
an eye on both free memory and the number of directory entries.

## Let the safety prompts do their job

Replacing a P9 in an IMG is a real change. EDIT950 makes that moment clear.

![The verified overwrite prompt with backup enabled](Images/edit950-verified-overwrite.png)

Leave **Create and verify a complete IMG backup first** enabled for anything you
care about. EDIT950 then:

1. copies the whole IMG;
2. checks the backup;
3. writes the replacement;
4. reads it back and compares it; and
5. restores the backup automatically if the checked operation fails.

This takes longer than a blind save, but it is the right trade for rescued
disks that may have no second copy.

## Use tags across EDIT950 and FIND950

Tags are musical notes attached to disks, programs or samples: favourites,
drums for a live set, dark pads, needs tuning, and so on.

![The shared tag-library settings](Images/edit950-shared-tag-settings.png)

EDIT950 and FIND950 use the same tag library. Tags do not consume sampler disk
space and are never written into P9, S9 or IMG files.

Use **Settings → Shared Tag Index** to reveal, move or export a copy of the tag
library. A synced folder is fine, but avoid changing tags on two Macs at the
same time.

## Choose which files Finder opens in EDIT950

Open **Settings → General → Finder File Associations** to make EDIT950 the
default application for IMG, P9 or S9 files, individually or together. EDIT950
warns before requesting this system-wide change. An IMG opens in the browser, a
P9 opens in the standalone program editor, and an S9 is offered for import into
the currently open writable IMG; the loose source file is never modified.

## Set the appearance and read diagnostics

Choose **System**, **Light** or **Dark** in Settings or the View menu. The choice
is shared across 950TOOLS applications that support it. Display zoom remains a
separate per-application setting.

EDIT950 keeps a rolling, size-limited diagnostic activity log. It records
application actions, helper commands, program-audition input/engine recovery
and errors, but not IMG, P9, S9 or audio contents. Home and temporary paths are
shortened. Open the viewer from the window or Settings, then use **Copy**,
**Save**, **Reveal** or **Clear** when a problem needs a readable report.

![The EDIT950 diagnostic activity log](Images/edit950-diagnostic-log.png)

## Work with FIND950

FIND950 is quicker when you do not yet know which disk contains the sound.

1. Find and audition the sound in FIND950.
2. Choose **Open in EDIT950** to open the exact disk.
3. Or choose **Export Program Through EDIT950…** to build a smaller IMG around
   one P9 and its samples.

FIND950 identifies the sound; EDIT950 asks where to write, performs the change
and checks the result.

## Work with PLAY950

Use **Open in PLAY950** when you want to play a program in the DAW. If the sound
needs changing, use PLAY950’s **Edit This IMG** button to bring the source back
to EDIT950.

After editing the IMG, return to PLAY950 and choose **Reload Source**. The DAW
keeps the previous playable sound if the reload fails.

## Use the result with hardware

EDIT950 changes the IMG file, not a physical disk or drive. Move the checked IMG
into the Gotek, USB or disk-writing routine you already trust.

EDIT950 and FIND950 coordinate use of removable volumes. Safe Eject stops before
cleanup if either app is scanning, exporting, auditioning or otherwise using the
same drive, and names the operation that must finish. No configured metadata is
removed in that case. Idle cached FIND950 browsing does not block eject.

Keep the rescued original separately. A working copy is for music-making; the
archive copy is for the future.

## Read the manual and check for updates

The recent-images screen links directly to this GitHub User Manual. Choose
**EDIT950 → Check for Updates…** at any time for an explicit result. EDIT950
also checks the latest GitHub release once when it launches. If a newer release
exists, a dismissible notice opens its GitHub release page so you can download
it yourself. EDIT950 never replaces or installs the application automatically.

## Quick fixes

### I can listen but cannot import, delete or save

The IMG is open read-only. Reopen a working copy with read-only mode switched
off. Do not make the only archival copy writable just for convenience.

### A WAV will not import

Use a mono PCM WAV. Very large files may not fit in the remaining sampler
memory. EDIT950 shows the estimated size before import.

### A program is silent after moving files around

The P9 probably refers to an S9 sample name that is not present. Open the
program and check its Soft and Loud sample choices, or use FIND950 to locate the
missing sample.

### My edited sample still sounds like the old one

Stop audition, select the sample again and replay it. If another app has the IMG
open, reload the source there as well.

### I am nervous about a save

Cancel, duplicate the IMG in Finder and work on the duplicate. When replacing a
program, leave the complete backup option enabled.

## A simple musical workflow

1. Open a copy of an IMG read-only and audition it.
2. Reopen the working copy as writable only when you know what you want to do.
3. Edit a program or sample and save a copy first.
4. Listen to the result.
5. Replace the item with backup and verification enabled.
6. Open the program in PLAY950 or move the checked IMG to your sampler setup.

The goal is not to turn music-making into data recovery. It is to make old
sounds playable again without gambling the only surviving disk image.
