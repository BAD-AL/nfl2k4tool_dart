# NFL 2K4 Gamesave Tool

Read, edit, and write NFL 2K4 Xbox and PS2 gamesave files. Export player,
coach, team, and schedule data as plain-text CSV; edit it in any text editor
or spreadsheet; apply it back to a save file.

Supports roster saves (`.dat`) and franchise saves (`.dat` / `.zip`).
Xbox saves are re-signed automatically on write. PS2 saves require no signing.

## CLI Usage

```
nfl2k4tool <savefile> [flags] [-out:<outfile>] [datafile]
```

`savefile` is required (Xbox `.dat`, Xbox `.zip`, or PS2 raw file).  
`datafile` is a text/csv file with the data you want to import.
`-out:<outfile>` is required whenever writing a modified save.

### Export flags

| Flag | Description |
|------|-------------|
| `-ab` | Export abilities and scalar attributes (Speed, Catch, etc.) |
| `-app` | Export appearance attributes (BodyType, Skin, Face, gear…) |
| `-fa` | Include Free Agents in output |
| `-allstar` | Include non-NFL teams (Challengers, Swamis, Alumni, All AFC/NFC/NFL) |
| `-team=xxx` | Export one team only (case-insensitive partial match, e.g. `-team=49ers`). Use `-team=fa` for Free Agents. |
| `-key=f1,f2,…` | Export exactly the listed fields in that order (overrides `-ab`/`-app`) |
| `-coach` | Export coach data (name, bio, body model, photo, record) |
| `-td` | Export team metadata (Nickname, Abbrev, City, Playbook…) |
| `-pc` | Prefix team export with `PlayerControlled=[…]` line (franchise only) |
| `-sch` | Export schedule (franchise only) |
| `-time` | Include kickoff times in schedule export |

### Modification flags

| Flag | Description |
|------|-------------|
| `-sortpos` | Reorder each team's player slots by position group. Requires `-out`. |
| `-krcheck` | Check KR/PR slots for invalid returner positions |
| `-fixkr` | Fix invalid KR/PR slots by rotating last CBs into those slots. Requires `-out`. Run after `-sortpos`. |
| `-fixskin` | Fix Skin/Face for players whose Photo matches the base roster but whose appearance doesn't. Requires `-out`. |

---

## Workflow

### 1 — Export player data

```bash
# All teams, abilities + appearance
nfl2k4tool roster.dat -ab -app > players.txt

# One team only
nfl2k4tool roster.dat -ab -team=eagles > eagles.txt

# Specific fields
nfl2k4tool roster.dat -key=Position,fname,lname,Speed,Catch > speed.txt

# Include free agents
nfl2k4tool roster.dat -ab -fa > all.txt
```

### 2 — Edit the text file

The exported file is plain CSV-like file. The `#header` line lists the fields in order.
Edit any values you like. You can remove rows or columns you don't want to
change — only the fields present in the header are touched on import.

```
#Position,fname,lname,Speed,Catch
QB,Tom,Brady,85,45
WR,Randy,Moss,97,98
```

### 3 — Apply edits back to the save

```bash
nfl2k4tool roster.dat players_edited.txt -out:roster_new.dat
```

The tool matches players by name and team. Fields not listed in the header are
left untouched.

### Coach data

```bash
# Export
nfl2k4tool roster.dat -coach > coaches.txt

# Import (coach data file uses CoachKEY= header, same apply syntax)
nfl2k4tool roster.dat coaches_edited.txt -out:roster_new.dat
```

Coach `Body` is specified as a bracketed name, e.g. `[Andy Reid]`. Raw numeric
indices are accepted for backward compatibility.

### Team data
'TeamData' is stuff like:
```
TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Playbook
TeamData,49ers,49ers,SF,San Francisco,SF,PB_49ers

# The TeamData strings are fixed-length. 
```

```bash
# Export
nfl2k4tool roster.dat -td > teams.txt

# Import
nfl2k4tool roster.dat teams_edited.txt -out:roster_new.dat
```

### Schedule (franchise saves only)

```bash
# Export
nfl2k4tool franchise.dat -sch > schedule.txt

# Import
nfl2k4tool franchise.dat schedule_edited.txt -out:franchise_new.dat
```


## PS2 Support

PS2 save files are raw binary with no application-level signing. The tool
detects the platform automatically by checking for the Xbox `VSAV` magic at
the start of the file:

- **Xbox** — `toBytes()` re-signs with HMAC-SHA1 before returning bytes
- **PS2** — `toBytes()` returns raw bytes, no signing step

Reading and writing player, coach, team, and schedule data works identically
on both platforms.

---

## Key field names

Player fields used in `-key=` and data file headers:

| Field | Notes |
|-------|-------|
| `fname`, `lname` | First and last name |
| `Team` | Team name (matches `kTeamNames`) |
| `Position` | QB, RB, WR, TE, OL, DL, LB, CB, S, K, P |
| `JerseyNumber` | |
| `Speed`, `Agility`, `Strength`, `Jumping` | Physical ratings |
| `Coverage`, `PassRush`, `Tackle` | Defensive ratings |
| `PassAccuracy`, `PassArmStrength`, `Scramble` | QB ratings |
| `Catch`, `RunRoute`, `BreakTackle` | Skill ratings |
| `PassBlocking`, `RunBlocking` | Line ratings |
| `KickPower`, `KickAccuracy` | Kicker/punter ratings |
| `Stamina`, `Durability`, `Composure`, `Consistency` | General ratings |
| `Photo`, `BodyType`, `Skin`, `Face`, `Dreads` | Appearance |
| `Helmet`, `FaceMask`, `Visor`, `EyeBlack` | Equipment |
| `College`, `DOB`, `YearsPro`, `Hand`, `Weight`, `Height` | Bio |

---

## Developer Guide

### Adding this library to a Dart project

```yaml
# pubspec.yaml
dependencies:
  nfl2k4tool_dart:
    path: ../nfl2k4tool_dart
```

### Core API

```dart
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';

// Load from bytes (dart:io, browser FileReader, etc.)
final save = NFL2K4Gamesave.fromBytes(bytes);

// Or load the embedded unmodified base roster
final save = NFL2K4Gamesave.fromBaseRoster();

// Platform detection
print(save.isXbox);       // true = Xbox, false = PS2
print(save.isFranchise);  // true = franchise save
```

### Exporting data as text

```dart
// Player data — RosterKey controls which fields appear
final text = save.toText(RosterKey.all);

// Filter to one team
final text = save.toText(RosterKey.abilities, teamIndex: kTeamNames.indexOf('Eagles'));

// Include free agents
final text = save.toText(RosterKey.abilities, includeFreeAgents: true);

// Include non-NFL teams (Alumni, All-Stars, etc.)
final text = save.toText(RosterKey.abilities, includeAllStarTeams: true);

// Coach, team, schedule
final coachText = save.toCoachDataText();
final teamText  = save.toTeamDataText();
final schedText = scheduleToText(save.getSchedule()); // franchise only
```

### Applying edited text back

```dart
// The text format toText() produces is exactly what InputParser consumes.
// Only fields present in the #header row are changed; everything else is untouched.
final result = InputParser(save).applyText(editedText, key: RosterKey.abilities);
print('${result.updated} updated, ${result.skipped} skipped');
if (result.errors.isNotEmpty) print(result.errors.join('\n'));
```

### Getting output bytes

```dart
// Re-signs automatically for Xbox; no-signing for PS2
final Uint8List bytes = save.toBytes();

// Re-pack into the original Xbox ZIP structure
final Uint8List zip = save.toZipBytes(); // throws if not loaded from ZIP
```

### Team index

Teams are ordered alphabetically in `kTeamNames` (index 0 = 49ers, 1 = Bears, …
31 = Vikings). Indices 32–42 are non-NFL teams (Challengers, Swamis, Alumni,
All-Star squads).

```dart
final idx = kTeamNames.indexOf('Eagles'); // 13
```

### Running tests

```bash
dart test
```

---

## Notes

Detailed binary format documentation lives in
`GAMESAVE_SECTIONS_2k4.md`.

`Claude Code` utilized in analysis of gamesave file and writing the code.
