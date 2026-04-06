# NFL 2K4 Gamesave Binary Format

Research notes for building NFL2K4Tool. Based on analysis of `base_roster_2k4_savegame.dat`,
`Vick_add_1_to_all_savegame.dat` (diff-based attribute mapping), and franchise saves.

Legend:
- ✓ **Confirmed** — verified against known player data or binary diff
- ~ **Inferred** — same offset as 2K5, not yet verified in 2K4
- ? **Unknown** — not yet determined

---

## Save Signing

| Field | Value | Status |
|-------|-------|--------|
| Key | `0x0BFF9916D00641950CBFAB3E313630A9` | ✓ |
| Algorithm | HMAC-SHA1 | ✓ |
| Signature location | File bytes 4..23 (20 bytes) | ✓ |
| Data signed | File bytes 24 onward (`bytes[24..]`) | ✓ |

Confirmed: recomputing HMAC-SHA1 over `bytes[24..]` with the key above exactly matches
the stored signature in both roster and franchise originals.

---

## File Container

| Field | Roster | Franchise | Status |
|-------|--------|-----------|--------|
| Format | VSAV (Xbox gamesave container) | VSAV | ✓ |
| ZIP container | `UDATA/53450022/<hex>/savegame.dat` | same | ✓ |
| ZIP detection | PK magic bytes `0x50 0x4B 0x03 0x04` at offset 0 | | ✓ |
| Header size | 24 bytes (0x00..0x17) | 24 bytes | ✓ |
| Game data start (`BASE`) | `0x18` | `0x1E0` | ✓ |
| All GD offsets | Relative to `BASE` | Relative to `BASE` | ✓ |

**Xbox ZIP saves:** The game distributes saves as ZIP archives containing the full
`UDATA/53450022/<hex>/` folder structure. Only `savegame.dat` is modified when saving;
all other ZIP entries are preserved. Title ID `53450022` is constant; the hex folder name
is a per-save random value.

---

## Pointer Resolution

```
dest_gd = ptr_gd + signed_i32le_value - 1
where ptr_gd = ptr_file_offset - BASE
```

---

## Player Array

| Field | Value | Status |
|-------|-------|--------|
| `kPlayerStartGd` | GD `0x0113A4` | ✓ |
| Stride (`kPlayerStride`) | `0x50` bytes (80 bytes) | ✓ |
| Record data extent | +0x00..+0x52 (3 bytes past stride boundary) | ✓ |

**Note on team block pointers:** Team block pointers resolve to `player_record_GD + 4`,
not the record start. Subtract 4 from any resolved team pointer to get the true record GD.

---

## Team Block

| Field | Value | Status |
|-------|-------|--------|
| `kTeamBlockGd` | GD `0x034A0` | ✓ |
| Stride (`kTeamStride`) | `0x1E0` bytes (480 bytes) | ✓ |
| Slots (`kTeamSlots`) | 43 total | ✓ |
| Player pointer slots per team | 65 × 4 bytes = 260 bytes (+0x00..+0x103) | ✓ |
| Team attribute section | +0x104..+0x1DF (220 bytes) | ~ (partially mapped) |

See "Team Block Ordering" section for the confirmed physical slot → team mapping.
Note: Vikings are at slot 42 (not slot 31); NE Alumni occupies slot 29.

### Team Attribute Section Layout (+0x104..+0x1DF)

| Offset | Size | Field | Status | Notes |
|--------|------|-------|--------|-------|
| +0x104 | 4 | storedID / Logo | ✓ | alpha index (0=49ers…31=Vikings; 33–46 for specials). Low byte = logo index (0–37). These are the same field. |
| +0x108 | 4 | ptr → city_name string | ✓ | Relative ptr; points into the same team string block as +0x110 (GD 0x0835xx–0x083cxx). e.g. "San Francisco", "Chicago" |
| +0x10C | 4 | ptr → team_nickname string | ✓ | Relative ptr; points into kTeamNicknameSectionGd (see External String Sections) |
| +0x110 | 4 | ptr → abbreviation string | ✓ | Relative ptr; 3-char abbreviation (e.g. "SF", "BUF") |
| +0x114 | 4 | ptr (negative) | ? | Relative pointer to earlier game data |
| +0x118 | 4 | ptr → storedID_string | ✓ | Relative ptr; 2-digit decimal string of THIS block's storedID |
| +0x11C | 4 | ptr → PlaybookAttributesSection | ? | Negative relative ptr; resolves into GD ~0x2720–0x2860 (see Playbook Attributes below) |
| +0x120 | 4 | player_count (low byte) + ? | ✓ | Low byte = 0x35 = 53 for all NFL teams |
| +0x121..+0x133 | 19 | **unknown** | ? | Mix of values, some zero |
| +0x134 | 4 | offense_playbook_idx? | ? | u32 (effective u8), range 0–7; 8 playbooks, consistent per team type |
| +0x138 | 4 | defense_playbook_idx? | ? | u32 (effective u8), range 0–8; 9 playbooks, value 1 never appears |
| +0x13C..+0x14F | 20 | relative pointers | ? | Several pointer-like values |
| +0x150 | var | jersey_table | ✓ | u16 zero-terminated array; see Jersey Table section below. Low byte also mirrors Logo (kTeamLogoMirrorOffset). |
| +0x17E | 1 | DefaultJersey | ✓ | Last byte of jersey table's 24-slot region; 0 = home jersey |
| +0x180 | 2 | **unknown** | ? | range 0–12+ after jersey table |
| +0x182 | 2 | **unknown** | ? | range 4–13+ |
| +0x184 | 2 | **unknown** | ? | large values 0x3400–0x6400; possibly team PBP audio index |
| +0x186 | 2 | **unknown** | ? | range 0–29, non-unique; possibly division/conference |
| +0x188 | 2 | **unknown** | ? | range 0–8 |
| +0x18A..+0x1DF | 86 | **unknown** | ? | |

### Jersey Table (+0x150)

Format: zero-terminated u16 array, padded with zeros to 48 bytes (24 u16s). Fixed fields
always begin at +0x180 regardless of jersey table length.

```
[teamID u16] [since_year u16] [current_year(2004) u16]
[year_start_1 u16] [year_end_1 u16]  ← historic jersey era 1
[year_start_2 u16] [year_end_2 u16]  ← historic jersey era 2
...
[year_alt_1 u16] [alt_num_1 u16]     ← alternate/throwback jersey
...
[0x0000]                              ← terminator
```

**Edge case:** 49ers have teamID=0, so the parser must handle the first u16 being 0
(teamID=0 is valid, not a terminator). Vikings have teamID=31 and since_year=0.

---

## External String Sections

These sections live outside the team block and are indexed separately. The code reads
them directly rather than following the team block's string pointers.

### Team Nickname / Abbreviation Section

| Field | Value | Status |
|-------|-------|--------|
| `kTeamNicknameSectionGd` | GD `0x8188E` | ✓ |
| Format | 32 pairs of UTF-16LE null-terminated strings: [Nickname, Abbrev] | ✓ |
| Ordering | Alphabetical by kTeamNames (0=49ers…31=Vikings) | ✓ |

To find team T's nickname: scan past T pairs from the section start (each pair = skip Nickname string then Abbrev string).

### Team Stadium / City Section

| Field | Value | Status |
|-------|-------|--------|
| `kTeamStadiumSectionGd` | GD `0x7F9B0` | ✓ |
| Format | Entries indexed by logo index (0–37); each entry is [ShortStadium, City, "sXX", LongStadium] as UTF-16LE null-terminated strings | ✓ |

The `"sXX"` sentinel (e.g. `"s25"` for logo 25) marks which logo index owns that entry. The code builds a cache mapping logo index → (shortOff, cityOff) at first access.

---

## Playbook Attributes Section

| Field | Value | Status |
|-------|-------|--------|
| GD range | `0x2738`–`0x2860` 24 bytes before = `0x2720` | ? |
| Format | 37 × 8-byte entries; each entry = two u32 GD addresses | ? |

Each team block's +0x11C pointer resolves into a sequential slot in this section (blocks 0–2 map to entries block 3 = entry 0 at `0x2738`). The two GD addresses per entry likely point to offense and defense playbook data objects in the game heap (`~GD 0x7F100–0x7F400`), which are all zeros in the base roster save (populated only during active franchise/game).

**Note:** The +0x11C pointer is not written by the tool. Only +0x134/+0x138 are candidates for playbook editing, pending confirmation.

---

## Free Agent Block

| Field | Value | Status |
|-------|-------|--------|
| `kFABlockGd` | GD `0x043BD4` | ✓ |
| Format | Same as team blocks: 4-byte relative pointers, zero-terminated | ✓ |
| Count (roster) | 191 entries | ✓ |
| Count (franchise) | 191 entries (base), grows as players released | ✓ |

Confirmed present in both roster (BASE=`0x18`) and franchise (BASE=`0x1E0`) files.
Verified by diffing franchise save before/after releasing one player (Brandon Doman, PBP=3556).

**What changes on player release (franchise):**
- New pointer appended to FA block
- Player's entry removed from team block, remaining pointers shift up, count decremented
- Player record `+0x26` bit 1 cleared (`0x12 → 0x10`)
- Counter at GD `0x80` incremented

Note: old heuristic (players not in any team block) found 226 instead of 191 — the
difference (35) is special characters (Challengers/Swamis/Legends) not in the FA block.

---

## Team Block Ordering

Physical block ordering confirmed via storedID (`uint32 LE`) at `+0x104` of each block.
The storedID is alphabetical team index (0=49ers … 31=Vikings; 33–46 for specials).

**The old "rotated-alphabetical" assumption was wrong.**

NFL teams do NOT fill a contiguous 0–31 range: block 29 holds NE Alumni (storedID=37),
and Vikings (storedID=31) are at block 42.

| Block | Team        | storedID | Block | Team        | storedID |
|-------|-------------|----------|-------|-------------|----------|
|  0    | Redskins    | 25       | 22    | Panthers    | 20       |
|  1    | Browns      |  5       | 23    | Rams        | 23       |
|  2    | Buccaneers  |  6       | 24    | Bengals     |  2       |
|  3    | Bills       |  3       | 25    | Texans      | 29       |
|  4    | Chargers    |  8       | 26    | Jets        | 17       |
|  5    | Titans      | 30       | 27    | Saints      | 26       |
|  6    | Seahawks    | 27       | 28    | Raiders     | 22       |
|  7    | 49ers       |  0       | **29**| **NE Alumni** | **37** |
|  8    | Ravens      | 24       | 30    | Steelers    | 28       |
|  9    | Eagles      | 13       | 31    | Giants      | 15       |
| 10    | Cowboys     | 11       | 32    | Challengers | 46       |
| 11    | Cardinals   |  7       | 33    | Swamis      | 33       |
| 12    | Falcons     | 14       | 34    | All AFC     | 40       |
| 13    | Patriots    | 21       | 35    | All NFC     | 41       |
| 14    | Bears       |  1       | 36    | All NFL     | 42       |
| 15    | Lions       | 18       | 37    | MW Alumni   | 43       |
| 16    | Dolphins    | 12       | 38    | SE Alumni   | 44       |
| 17    | Packers     | 19       | 39    | SW Alumni   | 45       |
| 18    | Chiefs      |  9       | 40    | FW Alumni   | 34       |
| 19    | Colts       | 10       | 41    | GP Alumni   | 35       |
| 20    | Broncos     |  4       | **42**| **Vikings** | **31** |
| 21    | Jaguars     | 16       |       |             |          |

All 32 NFL teams and all 11 special teams confirmed. ✓

---

## Player Record Layout

### College Pointer / Scalar (+0x04..+0x06)

College is stored as a **u24 LE** at +0x04..+0x06 using a slot-relative formula:

```
INI  = u24 − (kCollegeBase − slot × kPlayerStride)
slot = (recFile − BASE − kPlayerStartGd) ÷ kPlayerStride
kCollegeBase = 16774841  (0xFFF6B9)
```

INI values come from `2k4Colleges.ini`: 277 colleges, all multiples of 8 (0–2208).
Byte +0x07 is always `0xFF` — a separate field, do not overwrite.

Confirmed for Manning/Tennessee(768), Brady/Michigan(96), Garcia/San Jose State(816).

### Early Header (+0x00..+0x0F)

| Offset | Size | Field | Status | Notes |
|--------|------|-------|--------|-------|
| +0x00 | 4 | ? | ? | Not college ptr — first 3 bytes are college u24, byte 3 is 0xFF sentinel |
| +0x04 | 3 | College (u24 LE) | ✓ |  college  |
| +0x07 | 1 | (always 0xFF) | ✓ | Separate field — do not touch |
| +0x08 | 2 | **unknown** | ? | |
| +0x0A | 2 | PBP | ✓ | Play-by-play index (u16 LE); +6 from 2K5's +0x04 |
| +0x0C | 2 | Photo | ✓ | Photo index (u16 LE); +6 from 2K5's +0x06 |
| +0x0E | 1 | **unknown** | ? | Value 0x04 for all tested players |
| +0x0F | 1 | Helmet_LeftShoe_RightShoe | ✓ | +3 from 2K5's +0x0C |

**Helmet_LeftShoe_RightShoe bit packing:**
```
bit6       = Helmet       (0=Standard, 1=Revolution)
bits[5:3]  = RightShoe    (0..7)
bits[2:0]  = LeftShoe     (0..7)
```

### Name Pointers (+0x10..+0x17)

| Offset | Size | Field | Status |
|--------|------|-------|--------|
| +0x10 | 4 | fname_ptr | ✓ Same as 2K5 |
| +0x14 | 4 | lname_ptr | ✓ Same as 2K5 |

Name strings are UTF-16LE, null-terminated.

**Draft rookie name indices:** After advancing a franchise season, drafted rookies have
raw i32 values < 1000 at +0x10/+0x14 instead of valid string pointers. These are indices
into the game engine's internal name pool (not present in the save file). The tool outputs
them as `n<index>` (e.g. `n42`) and skips writing them back on import. Editing
post-draft franchise files beyond the first season is not fully supported.

### Appearance Bytes (+0x18..+0x22)

| Offset | Field | Bit Packing | Status |
|--------|-------|-------------|--------|
| +0x18 | Turtleneck_Body_EyeBlack_Hand_Dreads | bits[6:5]=Turtleneck; bits[4:3]=Body; bit2=EyeBlack; bit1=Hand; bit0=Dreads | ✓ |
| +0x19 | Skin | bits[5:3]=Skin (0=Lightest..5=Darkest) | ✓ 159/159 |
| +0x1A | DOB byte 1 | See DOB section | ✓ |
| +0x1B | DOB byte 2 | See DOB section | ✓ |
| +0x1C | MouthPiece_LeftGlove_Sleeves_NeckRoll | Same as 2K5 | ✓ |
| +0x1D | RightGlove_LeftWrist | Same as 2K5 | ✓ |
| +0x1E | RightWrist | bits[6:3]=RightWrist (+1 shift vs 2K5) | ✓ |
| +0x1F | RightElbow_LeftElbow | bits[7:4]=RightElbow; bits[3:0]=LeftElbow | ✓ |
| +0x20 | JerseyNumber (low 5 bits) | bits[7:3] | ✓ |
| +0x21 | JerseyNumber (high 2 bits) \| FaceMask \| Visor bit0 | bits[1:0]=JerseyNumber[6:5]; bits[6:2]=FaceMask; bit7=Visor_bit0 | ✓ |
| +0x22 | Face \| Visor bit1 | bits[4:1]=Face; bit0=Visor_bit1 | ✓ |

**JerseyNumber** (7-bit, spans +0x20 and +0x21):
```
JerseyNumber = ((data[+0x21] << 5) & 0x60) | ((data[+0x20] >> 3) & 0x1F)
```

**Visor / FaceShield** (spans +0x21 and +0x22):
```
visor = ((data[+0x22] & 0x01) << 1) | ((data[+0x21] >> 7) & 0x01)
  0 = None
  1 = Clear
  2 = Black
```

**Body encoding (+0x18 bits[4:3]):**
```
1 = Normal
2 = ExtraLarge
3 = Large       (physically the largest)
```

**Skin encoding (+0x19 bits[5:3]):** 0=Lightest..5=Darkest

**LeftGlove** (4-bit, spans +0x1C/+0x1D):
```
high2 = (data[+0x1C] >> 6) & 0x03
low2  = data[+0x1D] & 0x03
LeftGlove = (high2 << 2) | low2
```

**LeftWrist** (4-bit):
```
LeftWrist = (((data[+0x1E] << 8) | data[+0x1D]) >> 6) & 0x0F
```

**RightWrist** (2K4 uses bits[6:3], vs 2K5's bits[5:2]):
```
RightWrist = (data[+0x1E] >> 3) & 0x0F
```

**LeftElbow / RightElbow** (+0x1F):
```
LeftElbow  = data[+0x1F] & 0x0F
RightElbow = (data[+0x1F] >> 4) & 0x0F
```

### Middle Section (+0x23..+0x36)

**Not the same as 2K5.**

| Offset | Field | Status | Notes |
|--------|-------|--------|-------|
| +0x23..+0x25 | (always 0) | ✓ | |
| +0x26 | **unknown** | ? | Bit 1 cleared when player released to FA |
| +0x27 | YearsPro | ✓ | raw u8 |
| +0x28..+0x30 | **unknown** | ? | |
| +0x31 | Position | ✓ | QB=0,K=1,P=2,WR=3,CB=4,FS=5,SS=6,RB=7,FB=8,TE=9,OLB=10,ILB=11,C=12,G=13,T=14,DT=15,DE=16 |
| +0x32 | Weight | ✓ | stored = `weight_lbs - 150` |
| +0x33 | Height | ✓ | stored = total inches |
| +0x34 | (always 0) | ✓ | |
| +0x35 | **unknown** | ? | Range 67–99; not editable; composite rating? |
| +0x36 | (always 0) | ✓ | NOT the Overall rating |

### Ability Bytes (+0x37..+0x52)

All shifted +1 byte from 2K5.

| Offset | Field |
|--------|-------|
| +0x37 | Speed |
| +0x38 | Agility |
| +0x39 | PassArmStrength |
| +0x3A | Stamina |
| +0x3B | KickPower |
| +0x3C | Durability |
| +0x3D | Strength |
| +0x3E | Jumping |
| +0x3F | Coverage |
| +0x40 | RunRoute |
| +0x41 | Tackle |
| +0x42 | BreakTackle |
| +0x43 | PassAccuracy |
| +0x44 | PassReadCoverage |
| +0x45 | Catch |
| +0x46 | RunBlocking |
| +0x47 | PassBlocking |
| +0x48 | HoldOntoBall |
| +0x49 | PassRush |
| +0x4A | RunCoverage |
| +0x4B | KickAccuracy |
| +0x4C | **unknown** | (gap between KickAccuracy and Leadership) |
| +0x4D | Leadership |
| +0x4E | PowerRunStyle |
| +0x4F | Composure |
| +0x50 | Scramble | (**past stride boundary**) |
| +0x51 | Consistency | (**past stride boundary**) |
| +0x52 | Aggressiveness | (**past stride boundary**) |

Scramble/Consistency/Aggressiveness overlap the first 3 bytes of the next player slot
but precede that slot's fname pointer (+0x10), so no functional conflict.

---

## Schedule (Franchise Only)

| Field | Value | Status |
|-------|-------|--------|
| `kScheduleGd` | GD `0x9B483` (file offset `0x9B663` with BASE=`0x1E0`) | ✓ |
| Weeks | 17 | ✓ |
| Slots per week | 16 game slots + 1 null separator = 17 slots × 8 bytes = 136 bytes/week | ✓ |
| Total block size | 17 × 136 = 2312 bytes | ✓ |

**Game slot layout (8 bytes):**

| Byte | Field | Notes |
|------|-------|-------|
| 0 | home team index | 0–31 (same as kTeamNames) |
| 1 | away team index | 0–31 |
| 2 | month | 1–12 |
| 3 | day | 1–31 |
| 4 | year − 2000 | e.g. 3 = 2003 |
| 5 | hour | 0–23 |
| 6 | minute | 0–59 |
| 7 | flags | `0x07` on the last real game in the week and on the null separator; `0x00` elsewhere |

**Null slot:** all zero except flags byte 7. Home=0/Away=0/Month=0/Day=0 indicates empty.

**End-of-week marker:** The 17th slot (index 16) in each week is always a null separator.
Its flags byte carries `0x07` for the final week (week 17); earlier separators use `0x00`.

**Hard cap per week (`kGamesPerWeek`):**
```
[16, 16, 14, 14, 14, 14, 14, 14, 14, 14, 16, 16, 16, 16, 16, 16, 16]
 W1  W2  W3  W4  W5  W6  W7  W8  W9 W10 W11 W12 W13 W14 W15 W16 W17
```
Total capacity = 256 games. Confirmed from game engine behavior: adding a 15th game to
a mid-season week causes it to display as "TBD at TBD" in-game.

**Two-phase best-effort import algorithm:**
- Phase 1 — collect all game lines in file order; Week headers ignored for placement.
- Phase 2 — distribute games into weeks per `kGamesPerWeek` hard cap. Games beyond the
  256-game total capacity are dropped with a warning.

---

## Coach Data

### Coach Record Array

| Field | Value | Status |
|-------|-------|--------|
| `kCoachRecordGd` | GD `0x2840` (file `0x2858`) | ✓ |
| Stride (`kCoachStride`) | `0x48` bytes (72 bytes) | ✓ |
| Total records | 40 (32 NFL + 8 special/alumni) | ✓ |
| Ordering | kTeamNames alphabetical order (0=49ers … 31=Vikings) for NFL records | ✓ |

Access formula: `rec_file = BASE + kCoachRecordGd + teamIndex * kCoachStride`

**Note on team-block coach pointer:** Each team block has a relative pointer at `+0x14C`
that points to a coach record, but this pointer is **rotated by 7** relative to kTeamNames
order and should not be used for direct coach access. Use the formula above instead.

### Coach Record Layout (+0x00..+0x47)

| Offset | Size | Field | Status | Notes |
|--------|------|-------|--------|-------|
| +0x00 | 4 | FirstName ptr | ✓ | i32 LE relative → UTF-16LE string in coach string section |
| +0x04 | 4 | LastName ptr | ✓ | i32 LE relative → UTF-16LE string |
| +0x08 | 1 | Height | ✓ | inches (observed range 71–76) |
| +0x09 | 1 | (padding) | ✓ | always `0x00` |
| +0x0A | 2 | Weight | ✓ | u16 LE, pounds (observed range 180–260) |
| +0x0C | 1 | Body | ✓ | coach model index 0–37; see Body Model table below |
| +0x0D..+0x0F | 3 | **unknown** | ? | |
| +0x10 | 2 | SeasonsWithTeam | ✓ | u16 LE |
| +0x12 | 2 | TotalSeasons | ✓ | u16 LE |
| +0x14 | 2 | Wins | ✓ | u16 LE |
| +0x16 | 2 | Losses | ✓ | u16 LE |
| +0x18..+0x33 | 28 | **unknown stats** | ? | 14 × u16 LE; likely Ties, WinningSeasons, SuperBowls, PlayoffWins, etc. — offsets not yet confirmed for 2K4 |
| +0x34 | 4 | Info1 ptr | ✓ | i32 LE relative → UTF-16LE string |
| +0x38 | 4 | Info2 ptr | ✓ | i32 LE relative → UTF-16LE string |
| +0x3C | 4 | Info3 ptr | ✓ | i32 LE relative → UTF-16LE string (often empty `""`) |
| +0x40 | 4 | Info4 ptr | ✓ | i32 LE relative → UTF-16LE string (always empty `""` in base roster) |
| +0x44 | 2 | Photo | ✓ | u16 LE photo ID; see formula below |
| +0x46 | 2 | (padding) | ✓ | always `0x0000` |

### Coach String Section

| Field | Value | Status |
|-------|-------|--------|
| Start | GD `0x81BC6` (file `0x81BDE`) | ✓ |
| End (exclusive) | GD `0x83446` (file `0x8345E`) | ✓ |
| Length | `0x1880` bytes (6272 bytes) | ✓ |
| Encoding | UTF-16LE, null-terminated (`0x0000`) | ✓ |
| Slack in base roster | Zero — section is fully packed | ✓ |

All six string pointers per record (FirstName, LastName, Info1–Info4) point into this
section. Expanding a string requires the section to have trailing zero bytes as slack;
the base roster has none. String contractions free slack at the tail which can then be
used for subsequent expansions within the same write operation.

When shifting strings, **all 32 × 6 = 192 string pointers** must be adjusted for any
pointer whose destination falls at or after the point of modification.

### Photo ID Formula

For all 32 NFL coaches: `Photo = Body + 8000` (confirmed for all 32 NFL teams).

This formula does **not** hold for special-team body indices 31–36. Those models were
assigned independently of the photo system; their `Body + 8000` values resolve to
player-face photo IDs rather than coach photos.

### Body Model Table

| Index | Name | Notes |
|-------|------|-------|
| 0 | Dave McGinnis | Cardinals |
| 1 | Dan Reeves | Falcons |
| 2 | Brian Billick | Ravens |
| 3 | Gregg Williams | Bills |
| 4 | John Fox | Panthers |
| 5 | Dick Jauron | Bears |
| 6 | Marvin Lewis | Bengals |
| 7 | Bill Parcells | Cowboys |
| 8 | Mike Shanahan | Broncos |
| 9 | Steve Mariucci | Lions |
| 10 | Mike Sherman | Packers |
| 11 | Tony Dungy | Colts |
| 12 | Jack Del Rio | Jaguars |
| 13 | Dick Vermeil | Chiefs |
| 14 | Dave Wannstedt | Dolphins |
| 15 | Mike Tice | Vikings |
| 16 | Bill Belichick | Patriots |
| 17 | Jim Haslett | Saints |
| 18 | Jim Fassel | Giants |
| 19 | Herman Edwards | Jets |
| 20 | Bill Callahan | Raiders |
| 21 | Andy Reid | Eagles |
| 22 | Bill Cowher | Steelers |
| 23 | Mike Martz | Rams |
| 24 | Marty Schottenheimer | Chargers |
| 25 | Dennis Erickson | 49ers |
| 26 | Mike Holmgren | Seahawks |
| 27 | Jon Gruden | Buccaneers |
| 28 | Jeff Fisher | Titans |
| 29 | Steve Spurrier | Redskins |
| 30 | Butch Davis | Browns |
| 31 | Ghost Coach1 | Invisible; does throw a flag |
| 32 | No Coach1 | No model displayed |
| 33 | Generic 1 | Visible generic coach model |
| 34 | Ghost Coach2 | Invisible; does throw a flag |
| 35 | No Coach2 | No model displayed |
| 36 | Generic 2 | Visible generic coach model |
| 37 | Dom Capers | Texans |

Special indices 31–36 are used by special/alumni team coach records. Indices 33 and 36
render visible generic models; 31 and 34 are invisible but still interact with the game
(throw flags); 32 and 35 show nothing.

---

## Differences vs NFL 2K5 Summary

| What | 2K5 | 2K4 | Δ |
|------|-----|-----|---|
| PBP | +0x04 (u16) | +0x0A (u16) | +6 |
| Photo | +0x06 (u16) | +0x0C (u16) | +6 |
| Helmet_LeftShoe_RightShoe | +0x0C | +0x0F | +3 |
| fname_ptr / lname_ptr | +0x10 / +0x14 | +0x10 / +0x14 | 0 |
| Skin | +0x19 DOB byte 0 | **+0x19 bits[5:3]** | different |
| DOB | +0x19..+0x1B (3 bytes) | **+0x1A..+0x1B** (2 bytes) | different |
| Visor | unknown | **+0x21 bit7, +0x22 bit0** | confirmed |
| Middle section | known | **entirely different** | |
| Weight | +0x2A | +0x32 | +8 |
| Height | +0x2B | +0x33 | +8 |
| All ability bytes | +0x36..+0x51 | +0x37..+0x52 | +1 |
| Team block GD | `0x041C8` | **`0x034A0`** | different |
| Team stride | `0x1F4` (500) | **`0x1E0`** (480) | different |
| Team order | alphabetical | **non-trivial physical order** (see Team Block Ordering) | different |
| Team block ptr → record | points to record start | points to record_GD+4 | +4 |
| FA block | slot 33 in team block | **dedicated block at GD `0x043BD4`** | different |
