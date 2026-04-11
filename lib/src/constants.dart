// ignore_for_file: constant_identifier_names

/// VSAV header size; all game-data (GD) offsets are relative to this.
const int kBase = 0x18;

/// GD offset of the first player record in the player array.
const int kPlayerStartGd = 0x0113A4;

/// Bytes per player record slot (data extends to +0x52, 3 bytes past this).
const int kPlayerStride = 0x50;

/// Total player slots in the sequential player array (last valid index = 1981).
const int kMaxPlayerSlot = 1982;

/// GD offset of the first player name string (fname of the first player slot).
/// Same for both roster (BASE=0x18) and franchise (BASE=0x1E0).
const int kNameSectionStartGd = 0x086E0A;

/// GD offset of the end of the modifiable player name section, including
/// zero slack bytes (~1448 zeros).  All fname/lname strings live between
/// [kNameSectionStartGd] and this value.  ShiftDataDown/Up are bounded here.
/// Same for both roster and franchise.
const int kNameSectionEndGd = 0x09469E;

/// GD offset of the first team block entry (49ers, the first team alphabetically).
/// Confirmed: 49ers is 7 slots before the old assumed start (Cardinals at 0x041C0).
/// 0x041C0 - 7 * 0x1E0 = 0x034A0.
const int kTeamBlockGd = 0x034A0;

/// Bytes per team block entry.
const int kTeamStride = 0x1E0;

/// Total team slots (43): 32 NFL teams + 11 special teams (Challengers, Swamis,
/// regional Alumni teams, All AFC, All NFC, All NFL).
const int kTeamSlots = 43;

/// Max player pointers stored in the pointer section of each team block.
const int kTeamMaxPlayers = 65;

/// GD offset of the Free Agent pointer block.
/// Same format as team blocks: array of 4-byte relative pointers, zero-terminated.
/// Confirmed present in both roster (base=0x18) and franchise (base=0x1E0) files.
/// Verified by diffing a franchise save before/after releasing one player.
const int kFABlockGd = 0x043BD4;

/// GD offset of the team nickname/abbrev section.
/// Contains 32 pairs of [Nickname, Abbrev] UTF-16LE null-terminated strings,
/// ordered per kTeamNames[0..31].  Same GD for both roster and franchise.
const int kTeamNicknameSectionGd = 0x8188E;

/// GD offset of the team stadium/city section.
/// Contains 32 entries ordered by logo index (0–37); each entry is the sequence
/// [ShortStadium, City, "sXX", LongStadium] of UTF-16LE null-terminated strings,
/// where XX is the logo index.  Same GD for both roster and franchise.
const int kTeamStadiumSectionGd = 0x7F9B0;

/// Byte offset within a team block for the logo index byte (values 0–37).
/// Mirrored at +0x150 within the same block.
const int kTeamLogoOffset = 0x104;

/// Mirror offset for the logo byte within a team block.
const int kTeamLogoMirrorOffset = 0x150;

/// Byte offset within a team block for the default jersey index byte.
const int kTeamJerseyOffset = 0x17E;

/// GD offset of the user-controlled team table (franchise saves only).
/// 32 entries × 4 bytes, ordered per kTeamNames[0..31].
/// Byte 0 of each entry: 0x01 = user-controlled, 0x00 = CPU-controlled.
/// Confirmed by diffing DefFran2K4 (all teams user) vs DefFran49 (49ers only).
const int kTeamControlGd = 0x9B0EC;

/// Stride between entries in the user-controlled team table.
const int kTeamControlStride = 4;

/// GD offset of the first coach record (49ers, index 0 in kTeamNames order).
/// File offset 0x2858 - base 0x18 = GD 0x2840.
/// 32 NFL coach records, each [kCoachStride] bytes, in kTeamNames order.
const int kCoachRecordGd = 0x2840;

/// Bytes per coach record.
const int kCoachStride = 0x48;

/// GD offset of the coach string section start.
/// File 0x81BDE - base 0x18 = GD 0x81BC6.
/// All coach name/info strings (UTF-16LE) live in this section.
const int kCoachStringSectionGd = 0x81BC6;

/// GD offset of the coach string section end (exclusive).
/// File 0x8345E - base 0x18 = GD 0x83446.
/// Strings may expand/contract but never past this boundary.
const int kCoachStringSectionEndGd = 0x83446;

/// Coach body model names for NFL 2K4, indexed by the Body byte (0–37).
///
/// Each entry is the name of the coach whose likeness the model represents in
/// this game.  Indices 31–36 are used by the special/alumni team coaches and
/// have not yet been identified; they are mapped to "Unknown 1"–"Unknown 6"
/// until confirmed in testing.
///
/// On export, Body is written as `[Name]` (e.g. `[Dick Jauron]`).
/// On import, `[Name]` is looked up here; an unrecognised name is an error.
/// A plain numeric value (e.g. `5`) is also accepted for backward compatibility.
const List<String> kCoachBodyNames = [
  'Dave McGinnis',        // 0  — Cardinals
  'Dan Reeves',           // 1  — Falcons
  'Brian Billick',        // 2  — Ravens
  'Gregg Williams',       // 3  — Bills
  'John Fox',             // 4  — Panthers
  'Dick Jauron',          // 5  — Bears
  'Marvin Lewis',         // 6  — Bengals
  'Bill Parcells',        // 7  — Cowboys
  'Mike Shanahan',        // 8  — Broncos
  'Steve Mariucci',       // 9  — Lions
  'Mike Sherman',         // 10 — Packers
  'Tony Dungy',           // 11 — Colts
  'Jack Del Rio',         // 12 — Jaguars
  'Dick Vermeil',         // 13 — Chiefs
  'Dave Wannstedt',       // 14 — Dolphins
  'Mike Tice',            // 15 — Vikings
  'Bill Belichick',       // 16 — Patriots
  'Jim Haslett',          // 17 — Saints
  'Jim Fassel',           // 18 — Giants
  'Herman Edwards',       // 19 — Jets
  'Bill Callahan',        // 20 — Raiders
  'Andy Reid',            // 21 — Eagles
  'Bill Cowher',          // 22 — Steelers
  'Mike Martz',           // 23 — Rams
  'Marty Schottenheimer', // 24 — Chargers
  'Dennis Erickson',      // 25 — 49ers
  'Mike Holmgren',        // 26 — Seahawks
  'Jon Gruden',           // 27 — Buccaneers
  'Jeff Fisher',          // 28 — Titans
  'Steve Spurrier',       // 29 — Redskins
  'Butch Davis',          // 30 — Browns
  'Ghost Coach1',         // 31 — The invisible man, does throw a flag
  'No Coach1',            // 32 — no one
  'Generic 1',            // 33 — confirmed generic coach model
  'Ghost Coach2',         // 34 — The invisible man, does throw a flag
  'No Coach2',            // 35 — no one
  'Generic 2',            // 36 — confirmed generic coach model
  'Dom Capers',           // 37 — Texans
];

/// Ordered field names for coach data export/import.
/// Matches the CoachKEY= header written by [NFL2K4Gamesave.toCoachDataText].
const List<String> kCoachKeyFields = [
  'Coach', 'Team', 'FirstName', 'LastName', 'Info1', 'Info2', 'Info3',
  'Body', 'Photo', 'Wins', 'Losses', 'SeasonsWithTeam', 'TotalSeasons',
];

/// GD offset of the playbook pointer table.
/// 36 entries × 8 bytes: [name_ptr(4), abbrev_ptr(4)] per playbook slot.
/// Slots 0–31 are in kTeamNames alphabetical order; slots 32–35 are generics.
/// Same GD for both roster and franchise files.
const int kPlaybookTableGd = 0x002720;

/// Playbook token names in playbook table order (slots 0–35).
const List<String> kPlaybookNames = [
  'PB_49ers',      'PB_Bears',    'PB_Bengals',  'PB_Bills',
  'PB_Broncos',    'PB_Browns',   'PB_Buccaneers','PB_Cardinals',
  'PB_Chargers',   'PB_Chiefs',   'PB_Colts',    'PB_Cowboys',
  'PB_Dolphins',   'PB_Eagles',   'PB_Falcons',  'PB_Giants',
  'PB_Jaguars',    'PB_Jets',     'PB_Lions',    'PB_Packers',
  'PB_Panthers',   'PB_Patriots', 'PB_Raiders',  'PB_Rams',
  'PB_Ravens',     'PB_Redskins', 'PB_Saints',   'PB_Seahawks',
  'PB_Steelers',   'PB_Texans',   'PB_Titans',   'PB_Vikings',
  'PB_West_Coast', 'PB_General',  'PB_User_A',   'PB_User_B',
];

/// 2K4 team slot order — fully alphabetical across all 32 NFL teams (slots 0-31).
/// '49ers' sorts first (digit before letters). Slots 32-42 are special/alumni teams.
const List<String> kTeamNames = [
  '49ers',                                                              // 0
  'Bears', 'Bengals', 'Bills', 'Broncos', 'Browns', 'Buccaneers',     // 1-6
  'Cardinals', 'Chargers', 'Chiefs', 'Colts', 'Cowboys',              // 7-11
  'Dolphins', 'Eagles', 'Falcons', 'Giants', 'Jaguars', 'Jets',       // 12-17
  'Lions', 'Packers', 'Panthers', 'Patriots', 'Raiders', 'Rams',      // 18-23
  'Ravens', 'Redskins', 'Saints', 'Seahawks', 'Steelers',             // 24-28
  'Texans', 'Titans', 'Vikings',                                       // 29-31
  'Challengers', 'Swamis',                                             // 32-33
  'FW Alumni', 'GP Alumni', 'MW Alumni', 'NE Alumni',                  // 34-37
  'SE Alumni', 'SW Alumni',                                             // 38-39
  'All AFC', 'All NFC', 'All NFL',                                     // 40-42
];

/// Canonical position group order used when sorting a team's depth chart.
const List<String> kPosOrder = [
  'C', 'CB', 'DE', 'DT', 'FB', 'FS', 'G', 'RB',
  'ILB', 'K', 'OLB', 'P', 'QB', 'SS', 'T', 'TE', 'WR',
];

/// Sentinel value in [kTeamReturnerSlots] meaning "not assigned".
/// Slots are 1-based; 53 appears across many teams simultaneously in the
/// source data, indicating the game uses it as a "no returner" placeholder.
const int kNoReturnerSlot = 53;

/// Valid returner positions for KR/PR roles.
const Set<String> kValidReturnerPositions = {'CB', 'SS', 'FS', 'RB', 'FB', 'WR'};

/// Per-team KR/PR slot indices, sourced from NFL2K4_KR_PR_slots.csv.
/// Slot indices are 1-based. A value of [kNoReturnerSlot] means not assigned.
/// Order matches kTeamNames (alphabetical).
const List<({int pr, int kr1, int kr2})> kTeamReturnerSlots = [
  (pr:  6, kr1:  6, kr2: 26), // 49ers
  (pr: 53, kr1: 53, kr2: 26), // Bears
  (pr: 53, kr1: 25, kr2: 26), // Bengals
  (pr: 51, kr1: 41, kr2: 53), // Bills
  (pr:  3, kr1: 17, kr2: 51), // Broncos
  (pr: 51, kr1: 52, kr2: 49), // Browns
  (pr: 52, kr1: 26, kr2: 27), // Buccaneers
  (pr: 51, kr1: 49, kr2: 51), // Cardinals
  (pr: 50, kr1: 50, kr2: 51), // Chargers
  (pr: 53, kr1: 53, kr2: 27), // Chiefs
  (pr: 52, kr1: 25, kr2: 28), // Colts
  (pr: 53, kr1: 53, kr2: 28), // Cowboys
  (pr: 52, kr1: 52, kr2: 26), // Dolphins
  (pr: 27, kr1: 27, kr2: 52), // Eagles
  (pr:  9, kr1:  9, kr2: 52), // Falcons
  (pr: 26, kr1: 26, kr2: 28), // Giants
  (pr: 53, kr1: 53, kr2: 25), // Jaguars
  (pr: 51, kr1: 53, kr2: 51), // Jets
  (pr: 53, kr1: 53, kr2: 26), // Lions
  (pr: 51, kr1: 25, kr2: 50), // Packers
  (pr: 50, kr1: 50, kr2: 24), // Panthers
  (pr: 50, kr1: 51, kr2: 53), // Patriots
  (pr:  4, kr1: 28, kr2: 52), // Raiders
  (pr:  7, kr1: 50, kr2:  7), // Rams
  (pr:  8, kr1:  8, kr2: 26), // Ravens
  (pr: 29, kr1: 50, kr2: 29), // Redskins
  (pr: 52, kr1: 52, kr2: 26), // Saints
  (pr: 51, kr1: 25, kr2: 52), // Seahawks
  (pr: 51, kr1: 51, kr2: 52), // Steelers
  (pr: 24, kr1: 24, kr2: 53), // Texans
  (pr: 26, kr1: 26, kr2: 51), // Titans
  (pr: 52, kr1: 28, kr2: 25), // Vikings
];

/// 17-position scheme used by 2K4.
const List<String> kPositionNames = [
  'QB', 'K', 'P', 'WR', 'CB', 'FS', 'SS', 'RB', 'FB',
  'TE', 'OLB', 'ILB', 'C', 'G', 'T', 'DT', 'DE',
];

/// Ability field name → byte offset within player record.
/// All confirmed via diff analysis; all shifted +1 from 2K5.
const Map<String, int> kAbilityOffsets = {
  'Speed': 0x37,
  'Agility': 0x38,
  'PassArmStrength': 0x39,
  'Stamina': 0x3A,
  'KickPower': 0x3B,
  'Durability': 0x3C,
  'Strength': 0x3D,
  'Jumping': 0x3E,
  'Coverage': 0x3F,
  'RunRoute': 0x40,
  'Tackle': 0x41,
  'BreakTackle': 0x42,
  'PassAccuracy': 0x43,
  'PassReadCoverage': 0x44,
  'Catch': 0x45,
  'RunBlocking': 0x46,
  'PassBlocking': 0x47,
  'HoldOntoBall': 0x48,
  'PassRush': 0x49,
  'RunCoverage': 0x4A,
  'KickAccuracy': 0x4B,
  // +0x4C: gap (unknown)
  'Leadership': 0x4D,
  'PowerRunStyle': 0x4E,
  'Composure': 0x4F,
  'Scramble': 0x50,
  'Consistency': 0x51,
  'Aggressiveness': 0x52,
};

/// Ability field names in output column order (matches 2K5 tool format).
const List<String> kAbilityNames = [
  'Speed', 'Agility', 'Strength', 'Jumping', 'Coverage', 'PassRush',
  'RunCoverage', 'PassBlocking', 'RunBlocking', 'Catch', 'RunRoute',
  'BreakTackle', 'HoldOntoBall', 'PowerRunStyle', 'PassAccuracy',
  'PassArmStrength', 'PassReadCoverage', 'Tackle', 'KickPower', 'KickAccuracy',
  'Stamina', 'Durability', 'Leadership', 'Scramble', 'Composure',
  'Consistency', 'Aggressiveness',
];

/// PowerRunStyle raw byte values (same encoding as 2K5).
const int kPowerRunStyleFinesse  = 1;
const int kPowerRunStyleBalanced = 50;   // 0x32
const int kPowerRunStylePower    = 99;   // 0x63

String powerRunStyleName(int raw) {
  if (raw == kPowerRunStyleFinesse)  return 'Finesse';
  if (raw == kPowerRunStyleBalanced) return 'Balanced';
  if (raw == kPowerRunStylePower)    return 'Power';
  return raw.toString();
}

int powerRunStyleValue(String name) {
  switch (name) {
    case 'Finesse':  return kPowerRunStyleFinesse;
    case 'Balanced': return kPowerRunStyleBalanced;
    case 'Power':    return kPowerRunStylePower;
    default: return int.parse(name);
  }
}

const List<String> kSkinNames = [
  'Lightest', 'Light', 'LightMedium', 'DarkMedium', 'Dark', 'Darkest'
];

/// Maps a 2K5 skin value (Skin1–Skin22) to the closest 2K4 equivalent
/// (Skin1–Skin6).  Derived by cross-referencing players present in both games.
/// Values Skin7/Skin8 are not found in 2K5 rosters but are bucketed into Skin6
/// as the darkest fallback.  Any completely unrecognised value also maps to Skin6.
String mapSkin(String skinValue) {
  const skin1 = ['Skin1', 'Skin9',  'Skin17'];
  const skin2 = ['Skin2', 'Skin10', 'Skin18'];
  const skin3 = ['Skin3', 'Skin11', 'Skin19'];
  const skin4 = ['Skin4', 'Skin12', 'Skin20'];
  const skin5 = ['Skin5', 'Skin13', 'Skin21'];
  const skin6 = ['Skin6', 'Skin7',  'Skin8', 'Skin14', 'Skin15', 'Skin16', 'Skin22'];
  if (skin1.contains(skinValue)) return 'Skin1';
  if (skin2.contains(skinValue)) return 'Skin2';
  if (skin3.contains(skinValue)) return 'Skin3';
  if (skin4.contains(skinValue)) return 'Skin4';
  if (skin5.contains(skinValue)) return 'Skin5';
  if (skin6.contains(skinValue)) return 'Skin6';
  return 'Skin6'; // fallback for any value outside Skin1–Skin22
}

/// Maps a 2K5 face value to the closest 2K4 equivalent (Face1–Face15).
///
/// Face1–Face15 are identical between games.  2K5 also uses raw-integer
/// face values 16–22 (exported by both tools as bare numbers once the index
/// exceeds 14).  Mapping derived by cross-referencing 1456 matched players:
///   16 → Face1, 17 → Face2, 18 → Face3, 19 → Face4,
///   20 → Face5, 21 → Face6, 22 → Face15.
/// Raw 15 from a 2K4 round-trip is left unchanged (valid 4-bit index).
/// Any unrecognised value is returned unchanged so the caller can decide.
String mapFace(String faceValue) {
  const overRange = {
    '16': 'Face1', '17': 'Face2', '18': 'Face3', '19': 'Face4',
    '20': 'Face5', '21': 'Face6', '22': 'Face15',
  };
  return overRange[faceValue] ?? faceValue;
}

/// Binary encoding: 0=Skinny, 1=Normal, 2=ExtraLarge(CSV label), 3=Large(CSV label).
/// The CSV labels for Large/ExtraLarge appear swapped vs physical player size.
const List<String> kBodyNames = ['Skinny', 'Normal', 'ExtraLarge', 'Large'];

const List<String> kHandNames = ['Left', 'Right'];
const List<String> kHelmetNames = ['Standard', 'Revolution'];
const List<String> kVisorNames = ['None', 'Clear', 'Dark'];
const List<String> kTurtleneckNames = ['None', 'White', 'Black', 'Team'];
const List<String> kSleevesNames = ['None', 'White', 'Black', 'Team'];
const List<String> kNeckRollNames = [
  'None', 'Collar', 'Roll', 'Washboard', 'Bulging'
];
const List<String> kGloveNames = [
  'None', 'Type1', 'Type2', 'Type3', 'Type4',
  'Team1', 'Team2', 'Team3', 'Team4', 'Taped'
];
const List<String> kWristNames = [
  'None', 'SingleWhite', 'DoubleWhite', 'SingleBlack', 'DoubleBlack',
  'NeopreneSmall', 'NeopreneLarge', 'ElasticSmall', 'ElasticLarge',
  'SingleTeam', 'DoubleTeam', 'TapedSmall', 'TapedLarge', 'Quarterback',
];
const List<String> kElbowNames = [
  'None', 'White', 'Black', 'WhiteBlackStripe', 'BlackWhiteStripe',
  'BlackTeamStripe', 'Team', 'WhiteTeamStripe', 'Elastic', 'Neoprene',
  'WhiteTurf', 'BlackTurf', 'Taped', 'HighWhite', 'HighBlack', 'HighTeam',
];
const List<String> kShoeNames = [
  'Shoe1', 'Shoe2', 'Shoe3', 'Shoe4', 'Shoe5', 'Shoe6', 'Taped'
];
const List<String> kYesNoNames = ['No', 'Yes'];

/// HMAC-SHA1 key for 2K4 Xbox save signing.
const List<int> kXboxSignKey = [
  0x0B, 0xFF, 0x99, 0x16, 0xD0, 0x06, 0x41, 0x95,
  0x0C, 0xBF, 0xAB, 0x3E, 0x31, 0x36, 0x30, 0xA9,
];

/// Byte offset within the save file where the 20-byte HMAC-SHA1 signature lives.
const int kSignatureOffset = 4;
const int kSignatureLength = 20;

// ---------------------------------------------------------------------------
// College encoding
// ---------------------------------------------------------------------------

/// Base constant for the college encoding formula (empirically derived from
/// the base roster save file). The college value stored at player record
/// +0x04..+0x06 (u24 LE) equals:
///   kCollegeBase - slot × kPlayerStride + INI_value
/// where slot = (recFile − kBase − kPlayerStartGd) ÷ kPlayerStride.
const int kCollegeBase = 16774841;

/// Normalises 2K5 college name spellings to their 2K4 equivalents.
/// Names not present in this map and not found directly in [kCollegeINI]
/// will fall back to 'None'.
const Map<String, String> kCollegeNormalize = {
  'Albany State, GA':      'Albany State (GA)',
  'Augustana, SD':         'Augustana (SD)',
  'Central Missouri St':   'Central Missouri State',
  'Delaware':              'University of Delaware',
  'East Tennessee St':     'East Tennessee State',
  'Fort Valley St, GA':    'Fort Valley State (Ga.)',
  'Indiana, PA':           'Indiana (PA)',
  'Miami, FL':             'Miami (Fla.)',
  'Miami, OH':             'Miami (Ohio)',
  'Middle Tennessee St':   'Middle Tennessee St.',
  'Missouri Southern St':  'Missouri Southern St.',
  'Mt. San Antonio J.C.':  'Mount San Antonio J.C.',
  'North Carolina St':     'North Carolina State',
  'NW Missouri St':        'Northwest Missouri St.',
  'NW Oklahoma St':        'Northwest Oklahoma St.',
  'South Carolina St':     'South Carolina State',
  'Southern Conn. St':     'Southern Connecticut St.',
  'Southern Miss':         'Southern Mississippi',
  'Tarleton State, TX':    'Tarleton State (Texas)',
  'TX A&M-Kingsville':     'Texas A&M-Kingsville',
  'Wayne State, NE':       'Wayne State, Neb.',
  'WI-Stevens Pt.':        'Wisconsin-Stevens Pt.',
  'WI-Whitewater':         'Wisconsin-Whitewater',
};

/// College INI offset → college name (277 entries from 2k4Colleges.ini).
const Map<int, String> kCollegeByINI = {
  0: 'Clemson',
  8: 'Duke',
  16: 'Florida State',
  24: 'Georgia Tech',
  32: 'Maryland',
  40: 'North Carolina',
  48: 'North Carolina State',
  56: 'Virginia',
  64: 'Wake Forest',
  72: 'Illinois',
  80: 'Indiana',
  88: 'Iowa',
  96: 'Michigan',
  104: 'Michigan State',
  112: 'Minnesota',
  120: 'Northwestern',
  128: 'Ohio State',
  136: 'Penn State',
  144: 'Purdue',
  152: 'Wisconsin',
  160: 'Baylor',
  168: 'Colorado',
  176: 'Iowa State',
  184: 'Kansas',
  192: 'Kansas State',
  200: 'Missouri',
  208: 'Nebraska',
  216: 'Oklahoma',
  224: 'Oklahoma State',
  232: 'Texas',
  240: 'Texas A&M',
  248: 'Texas Tech',
  256: 'Boston College',
  264: 'Miami (Fla.)',
  272: 'Pittsburgh',
  280: 'Rutgers',
  288: 'Syracuse',
  296: 'Virginia Tech',
  304: 'West Virginia',
  312: 'Temple',
  320: 'Arkansas State',
  328: 'Boise State',
  336: 'Idaho',
  344: 'New Mexico State',
  352: 'North Texas',
  360: 'Utah State',
  368: 'Army',
  376: 'Cincinnati',
  384: 'East Carolina',
  392: 'Houston',
  400: 'Louisville',
  408: 'Memphis',
  416: 'Southern Mississippi',
  424: 'Tulane',
  432: 'Alabama-Birmingham',
  440: 'Akron',
  448: 'Bowling Green',
  456: 'Buffalo',
  464: 'Kent State',
  472: 'Marshall',
  480: 'Miami (Ohio)',
  488: 'Ohio',
  496: 'Ball State',
  504: 'Central Michigan',
  512: 'Eastern Michigan',
  520: 'Northern Illinois',
  528: 'Toledo',
  536: 'Western Michigan',
  544: 'Air Force',
  552: 'BYU',
  560: 'Colorado State',
  568: 'New Mexico',
  576: 'San Diego State',
  584: 'UNLV',
  592: 'Utah',
  600: 'Wyoming',
  608: 'Oregon',
  616: 'Washington',
  624: 'Oregon State',
  632: 'Arizona',
  640: 'Arizona State',
  648: 'California',
  656: 'UCLA',
  664: 'Stanford',
  672: 'Washington State',
  680: 'USC',
  688: 'Alabama',
  696: 'Arkansas',
  704: 'Auburn',
  712: 'Florida',
  720: 'Georgia',
  728: 'Kentucky',
  736: 'Louisiana State',
  744: 'Ole Miss',
  752: 'Mississippi State',
  760: 'South Carolina',
  768: 'Tennessee',
  776: 'Vanderbilt',
  784: 'Fresno State',
  792: 'Hawaii',
  800: 'Nevada',
  808: 'Rice',
  816: 'San Jose State',
  824: 'SMU',
  832: 'TCU',
  840: 'UTEP',
  848: 'Tulsa',
  856: 'Middle Tennessee St.',
  864: 'Central Florida',
  872: 'Louisiana Tech',
  880: 'Navy',
  888: 'Louisiana-Monroe',
  896: 'Notre Dame',
  904: 'Louisiana-Lafayette',
  912: 'Connecticut',
  920: 'South Florida',
  928: 'Troy State',
  936: 'Eastern Illinois',
  944: 'Furman',
  952: 'Northern Iowa',
  960: 'Georgia Southern',
  968: 'Samford',
  976: 'Southern Utah',
  984: 'SE Missouri State',
  992: 'Chattanooga',
  1000: 'Montana',
  1008: 'Weber State',
  1016: 'Abilene Christian',
  1024: 'Alabama A&M',
  1032: 'Alabama State',
  1040: 'Alcorn State',
  1048: 'Appalachian State',
  1056: 'Arkansas-Pine Bluff',
  1064: 'Augustana (SD)',
  1072: 'Austin Peay State',
  1080: 'Bethune-Cookman',
  1088: 'Bradley',
  1096: 'Brown',
  1104: 'Butte JC',
  1112: 'C.W. Post',
  1120: 'Cal Poly SLO',
  1128: 'Carson-Newman',
  1136: 'Central Florida CC',
  1144: 'Central Missouri State',
  1152: 'Central Oklahoma',
  1160: 'Central State',
  1168: 'Central Washington',
  1176: 'Cheyney',
  1184: 'Columbia',
  1192: 'Cornell',
  1200: 'Dartmouth',
  1208: 'Delaware St',
  1216: 'East Tennessee State',
  1224: 'Eastern Kentucky',
  1232: 'Eastern Washington',
  1240: 'Emporia State',
  1248: 'Evangel',
  1256: 'Florida A&M',
  1264: 'Fort Valley State (Ga.)',
  1272: 'Grambling',
  1280: 'Grand Valley State',
  1288: 'Grove City',
  1296: 'Hampton',
  1304: 'Harvard',
  1312: 'Hastings',
  1320: 'Hofstra',
  1328: 'Howard',
  1336: 'Illinois State',
  1344: 'Indiana (PA)',
  1352: 'Itawamba J.C.',
  1360: 'Jackson State',
  1368: 'Jacksonville State',
  1376: 'James Madison',
  1384: 'John Carroll',
  1392: 'Kentucky State',
  1400: 'Knoxville',
  1408: 'Kutztown',
  1416: 'Lambuth',
  1424: 'Lehigh',
  1432: 'Liberty',
  1440: 'Maine',
  1448: 'Massachusetts',
  1456: 'McGill',
  1464: 'McNeese State',
  1472: 'Midwestern State',
  1480: 'Millersville',
  1488: 'Mississippi',
  1496: 'Mississippi Valley',
  1504: 'Missouri Southern St.',
  1512: 'Montana State',
  1520: 'Morris Brown',
  1528: 'Mount San Antonio J.C.',
  1536: 'Murray State',
  1544: 'Nebraska-Omaha',
  1552: 'New Hampshire',
  1560: 'None',
  1568: 'North Alabama',
  1576: 'North Carolina A&T',
  1584: 'North Dakota',
  1592: 'North Dakota State',
  1600: 'Northeast Louisiana',
  1608: 'Northern Arizona',
  1616: 'Northern Colorado',
  1624: 'Northwest Missouri St.',
  1632: 'Northwest Oklahoma St.',
  1640: 'Northwestern State',
  1648: 'Ohio Northern',
  1656: 'Pennsylvania',
  1664: 'Pittsburgh State',
  1672: 'Portland State',
  1680: 'Princeton',
  1688: 'Rhode Island',
  1696: 'Richmond',
  1704: 'Robert Morris',
  1712: 'Rowan',
  1720: 'Sacramento State',
  1728: 'Saginaw Valley',
  1736: 'Sam Houston State',
  1744: 'Santa Clara',
  1752: 'Savannah State',
  1760: 'Shepherd',
  1768: 'Sonoma State',
  1776: 'South Carolina State',
  1784: 'South Dakota',
  1792: 'South Dakota State',
  1800: 'Southern Connecticut St.',
  1808: 'Southern Methodist',
  1816: 'Southern University',
  1824: 'Southwest Missouri State',
  1832: 'St. Cloud State',
  1840: 'Stephen F. Austin',
  1848: 'Tarleton State (Texas)',
  1856: 'Tennessee State',
  1864: 'Tenn-Chattanooga',
  1872: 'Tennessee-Martin',
  1880: 'Texas A&M-Com',
  1888: 'Texas A&M-Kingsville',
  1896: 'Texas Christian',
  1904: 'Texas Southern',
  1912: 'The Citadel',
  1920: 'Towson State',
  1928: 'Tuskegee',
  1936: 'UC Davis',
  1944: 'University of Delaware',
  1952: 'Valdosta State',
  1960: 'Villanova',
  1968: 'Virginia Union',
  1976: 'Wayne State, Neb.',
  1984: 'West Texas A&M',
  1992: 'Western Carolina',
  2000: 'Western Illinois',
  2008: 'Western Kentucky',
  2016: 'William & Mary',
  2024: 'Winston-Salem State',
  2032: 'Wisconsin-La Crosse',
  2040: 'Wisconsin-Stevens Pt.',
  2048: 'Wisconsin-Stout',
  2056: 'Wisconsin-Whitewater',
  2064: 'Yale',
  2072: 'Youngstown State',
  2080: 'Williams',
  2088: 'Mars Hill',
  2096: 'Morgan State',
  2104: 'Albany State (GA)',
  2112: 'Drake',
  2120: 'Brooklyn College',
  2128: 'Delta College',
  2136: 'Eastern Connecticut State',
  2144: 'Gateway Technical College',
  2152: 'Monroe College',
  2160: 'NYU',
  2168: 'Summerville',
  2176: 'Three Rivers College',
  2184: 'University of Regina',
  2192: 'West Virgina State',
  2200: 'Western New Mexico',
  2208: 'Crazy Taxi College',
};

/// College name → INI offset (reverse lookup).
const Map<String, int> kCollegeINI = {
  'Clemson': 0,
  'Duke': 8,
  'Florida State': 16,
  'Georgia Tech': 24,
  'Maryland': 32,
  'North Carolina': 40,
  'North Carolina State': 48,
  'Virginia': 56,
  'Wake Forest': 64,
  'Illinois': 72,
  'Indiana': 80,
  'Iowa': 88,
  'Michigan': 96,
  'Michigan State': 104,
  'Minnesota': 112,
  'Northwestern': 120,
  'Ohio State': 128,
  'Penn State': 136,
  'Purdue': 144,
  'Wisconsin': 152,
  'Baylor': 160,
  'Colorado': 168,
  'Iowa State': 176,
  'Kansas': 184,
  'Kansas State': 192,
  'Missouri': 200,
  'Nebraska': 208,
  'Oklahoma': 216,
  'Oklahoma State': 224,
  'Texas': 232,
  'Texas A&M': 240,
  'Texas Tech': 248,
  'Boston College': 256,
  'Miami (Fla.)': 264,
  'Pittsburgh': 272,
  'Rutgers': 280,
  'Syracuse': 288,
  'Virginia Tech': 296,
  'West Virginia': 304,
  'Temple': 312,
  'Arkansas State': 320,
  'Boise State': 328,
  'Idaho': 336,
  'New Mexico State': 344,
  'North Texas': 352,
  'Utah State': 360,
  'Army': 368,
  'Cincinnati': 376,
  'East Carolina': 384,
  'Houston': 392,
  'Louisville': 400,
  'Memphis': 408,
  'Southern Mississippi': 416,
  'Tulane': 424,
  'Alabama-Birmingham': 432,
  'Akron': 440,
  'Bowling Green': 448,
  'Buffalo': 456,
  'Kent State': 464,
  'Marshall': 472,
  'Miami (Ohio)': 480,
  'Ohio': 488,
  'Ball State': 496,
  'Central Michigan': 504,
  'Eastern Michigan': 512,
  'Northern Illinois': 520,
  'Toledo': 528,
  'Western Michigan': 536,
  'Air Force': 544,
  'BYU': 552,
  'Colorado State': 560,
  'New Mexico': 568,
  'San Diego State': 576,
  'UNLV': 584,
  'Utah': 592,
  'Wyoming': 600,
  'Oregon': 608,
  'Washington': 616,
  'Oregon State': 624,
  'Arizona': 632,
  'Arizona State': 640,
  'California': 648,
  'UCLA': 656,
  'Stanford': 664,
  'Washington State': 672,
  'USC': 680,
  'Alabama': 688,
  'Arkansas': 696,
  'Auburn': 704,
  'Florida': 712,
  'Georgia': 720,
  'Kentucky': 728,
  'Louisiana State': 736,
  'Ole Miss': 744,
  'Mississippi State': 752,
  'South Carolina': 760,
  'Tennessee': 768,
  'Vanderbilt': 776,
  'Fresno State': 784,
  'Hawaii': 792,
  'Nevada': 800,
  'Rice': 808,
  'San Jose State': 816,
  'SMU': 824,
  'TCU': 832,
  'UTEP': 840,
  'Tulsa': 848,
  'Middle Tennessee St.': 856,
  'Central Florida': 864,
  'Louisiana Tech': 872,
  'Navy': 880,
  'Louisiana-Monroe': 888,
  'Notre Dame': 896,
  'Louisiana-Lafayette': 904,
  'Connecticut': 912,
  'South Florida': 920,
  'Troy State': 928,
  'Eastern Illinois': 936,
  'Furman': 944,
  'Northern Iowa': 952,
  'Georgia Southern': 960,
  'Samford': 968,
  'Southern Utah': 976,
  'SE Missouri State': 984,
  'Chattanooga': 992,
  'Montana': 1000,
  'Weber State': 1008,
  'Abilene Christian': 1016,
  'Alabama A&M': 1024,
  'Alabama State': 1032,
  'Alcorn State': 1040,
  'Appalachian State': 1048,
  'Arkansas-Pine Bluff': 1056,
  'Augustana (SD)': 1064,
  'Austin Peay State': 1072,
  'Bethune-Cookman': 1080,
  'Bradley': 1088,
  'Brown': 1096,
  'Butte JC': 1104,
  'C.W. Post': 1112,
  'Cal Poly SLO': 1120,
  'Carson-Newman': 1128,
  'Central Florida CC': 1136,
  'Central Missouri State': 1144,
  'Central Oklahoma': 1152,
  'Central State': 1160,
  'Central Washington': 1168,
  'Cheyney': 1176,
  'Columbia': 1184,
  'Cornell': 1192,
  'Dartmouth': 1200,
  'Delaware St': 1208,
  'East Tennessee State': 1216,
  'Eastern Kentucky': 1224,
  'Eastern Washington': 1232,
  'Emporia State': 1240,
  'Evangel': 1248,
  'Florida A&M': 1256,
  'Fort Valley State (Ga.)': 1264,
  'Grambling': 1272,
  'Grand Valley State': 1280,
  'Grove City': 1288,
  'Hampton': 1296,
  'Harvard': 1304,
  'Hastings': 1312,
  'Hofstra': 1320,
  'Howard': 1328,
  'Illinois State': 1336,
  'Indiana (PA)': 1344,
  'Itawamba J.C.': 1352,
  'Jackson State': 1360,
  'Jacksonville State': 1368,
  'James Madison': 1376,
  'John Carroll': 1384,
  'Kentucky State': 1392,
  'Knoxville': 1400,
  'Kutztown': 1408,
  'Lambuth': 1416,
  'Lehigh': 1424,
  'Liberty': 1432,
  'Maine': 1440,
  'Massachusetts': 1448,
  'McGill': 1456,
  'McNeese State': 1464,
  'Midwestern State': 1472,
  'Millersville': 1480,
  'Mississippi': 1488,
  'Mississippi Valley': 1496,
  'Missouri Southern St.': 1504,
  'Montana State': 1512,
  'Morris Brown': 1520,
  'Mount San Antonio J.C.': 1528,
  'Murray State': 1536,
  'Nebraska-Omaha': 1544,
  'New Hampshire': 1552,
  'None': 1560,
  'North Alabama': 1568,
  'North Carolina A&T': 1576,
  'North Dakota': 1584,
  'North Dakota State': 1592,
  'Northeast Louisiana': 1600,
  'Northern Arizona': 1608,
  'Northern Colorado': 1616,
  'Northwest Missouri St.': 1624,
  'Northwest Oklahoma St.': 1632,
  'Northwestern State': 1640,
  'Ohio Northern': 1648,
  'Pennsylvania': 1656,
  'Pittsburgh State': 1664,
  'Portland State': 1672,
  'Princeton': 1680,
  'Rhode Island': 1688,
  'Richmond': 1696,
  'Robert Morris': 1704,
  'Rowan': 1712,
  'Sacramento State': 1720,
  'Saginaw Valley': 1728,
  'Sam Houston State': 1736,
  'Santa Clara': 1744,
  'Savannah State': 1752,
  'Shepherd': 1760,
  'Sonoma State': 1768,
  'South Carolina State': 1776,
  'South Dakota': 1784,
  'South Dakota State': 1792,
  'Southern Connecticut St.': 1800,
  'Southern Methodist': 1808,
  'Southern University': 1816,
  'Southwest Missouri State': 1824,
  'St. Cloud State': 1832,
  'Stephen F. Austin': 1840,
  'Tarleton State (Texas)': 1848,
  'Tennessee State': 1856,
  'Tenn-Chattanooga': 1864,
  'Tennessee-Martin': 1872,
  'Texas A&M-Com': 1880,
  'Texas A&M-Kingsville': 1888,
  'Texas Christian': 1896,
  'Texas Southern': 1904,
  'The Citadel': 1912,
  'Towson State': 1920,
  'Tuskegee': 1928,
  'UC Davis': 1936,
  'University of Delaware': 1944,
  'Valdosta State': 1952,
  'Villanova': 1960,
  'Virginia Union': 1968,
  'Wayne State, Neb.': 1976,
  'West Texas A&M': 1984,
  'Western Carolina': 1992,
  'Western Illinois': 2000,
  'Western Kentucky': 2008,
  'William & Mary': 2016,
  'Winston-Salem State': 2024,
  'Wisconsin-La Crosse': 2032,
  'Wisconsin-Stevens Pt.': 2040,
  'Wisconsin-Stout': 2048,
  'Wisconsin-Whitewater': 2056,
  'Yale': 2064,
  'Youngstown State': 2072,
  'Williams': 2080,
  'Mars Hill': 2088,
  'Morgan State': 2096,
  'Albany State (GA)': 2104,
  'Drake': 2112,
  'Brooklyn College': 2120,
  'Delta College': 2128,
  'Eastern Connecticut State': 2136,
  'Gateway Technical College': 2144,
  'Monroe College': 2152,
  'NYU': 2160,
  'Summerville': 2168,
  'Three Rivers College': 2176,
  'University of Regina': 2184,
  'West Virgina State': 2192,
  'Western New Mexico': 2200,
  'Crazy Taxi College': 2208,
};
