# S950 P9 native-format evidence

## Keygroup filter/modulation fields

The S950 P9 keygroup record is 70 bytes (`0x46`). Offsets below are relative to
the start of one keygroup record.

| Offset | Field | Encoding | Evidence |
|---:|---|---|---|
| `0x08` | Key-filter | unsigned native `0...99` | Hardware-saved two-keygroup differential fixture |
| `0x16` | LFO Depth | unsigned native `0...99` | Physical S950 display and hardware-saved fixture |

A privately owned two-keygroup program was saved on a physical S950 with
Key-filter 0 in the first keygroup and Key-filter 99 in the second. Their
records differ at `0x08` by exactly `0x00` versus `0x63` for that control.
Both records contain `0x32` at `0x16`, and the sampler shows LFO Depth 50.
This proves the fields are independent without distributing the fixture.

Other record differences in that fixture are the deliberately different key
ranges (`0x00`/`0x01`) and sampler-maintained next-keygroup runtime address
(`0x44`/`0x45`). They are not parameter candidates.

The model writes Key-filter and LFO Depth only to their proven offsets and
continues to preserve every unmodelled byte during unrelated edits.

## Build 32 physical-S950 round trip

On 9 August 2026, a generated test P9 was loaded on a physical S950. The sampler
displayed Key-filter 50, LFO Depth 0 and Constant Pitch off. Its filter opened
audibly as the played pitch rose from C2 through C3 to C4, confirming the
intended Key-filter response.

The sampler also displayed the programmed neutral values: VCF envelope
0/0/99 with amount +00, amplitude envelope 1/0/99/0, Filter 50, Loudness +00,
and zero velocity sensitivity for Loudness, Attack, Filter and Release.

After saving on the S950 and exporting again, the returned 108-byte P9 differed
from the generated source only at the sampler-maintained program RAM address
(`0x12...0x13`) and sample RAM address (`0x4e...0x4f`). Key-filter remained
`0x32` at keygroup-relative `0x08`,
LFO Depth remained `0x00` at keygroup-relative `0x16`, and every musical
parameter byte was preserved.
