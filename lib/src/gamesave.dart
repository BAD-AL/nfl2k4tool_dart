import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:dart_mymc/dart_mymc.dart';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';
import 'base_roster.dart';
import 'constants.dart';
import 'data_map.dart';
import 'player_record.dart';
import 'roster_key.dart';
import 'schedule.dart';

/// The game title ID embedded in Xbox ZIP saves.
const String kXboxTitleId = '53450022';

/// The PS2 product code prefix for NFL 2K4 saves.
const String kPs2TitleId = 'BASLUS-20727';

/// Loads and manipulates an NFL 2K4 Xbox gamesave (roster or franchise).
class NFL2K4Gamesave {
  final Uint8List _data;
  final int _base;

  /// Non-null when this save was loaded from a ZIP file.
  /// Holds the original archive (all entries intact) so we can swap
  /// savegame.dat and re-emit the full ZIP on [saveToFile].
  Archive? _zipArchive;

  /// The ZIP entry path for savegame.dat, e.g.
  /// "UDATA/53450022/AABBCCDD1234/savegame.dat".
  String? _zipEntryPath;

  /// Non-null when loaded from a PS2 PSU or MAX container.
  /// The PS2 directory name, e.g. 'BASLUS-20727BaseRos'.
  String? _ps2DirName;

  /// Side files from a PS2 PSU/MAX save (icon.sys, VIEW.ICO, etc.)
  /// preserved so round-trip saves retain the original icon data.
  Map<String, Uint8List>? _ps2SideFiles;

  NFL2K4Gamesave._(this._data, this._base);

  /// Detects the base offset by searching for the ROST magic (52 4F 53 54).
  /// Roster files have it at 0x18; franchise files have it at 0x1E0.
  /// Falls back to kBase (0x18) if not found.
  static int _detectBase(Uint8List data) {
    const rost = [0x52, 0x4F, 0x53, 0x54];
    for (int i = 0; i <= data.length - 4; i++) {
      if (data[i] == rost[0] && data[i + 1] == rost[1] &&
          data[i + 2] == rost[2] && data[i + 3] == rost[3]) {
        return i;
      }
    }
    return kBase;
  }

  factory NFL2K4Gamesave.fromBytes(List<int> bytes) {
    final raw = Uint8List.fromList(bytes);
    // ZIP magic: PK\x03\x04
    if (raw.length > 4 &&
        raw[0] == 0x50 && raw[1] == 0x4B &&
        raw[2] == 0x03 && raw[3] == 0x04) {
      return NFL2K4Gamesave._fromZipBytes(raw);
    }
    return NFL2K4Gamesave._(raw, _detectBase(raw));
  }

  factory NFL2K4Gamesave._fromZipBytes(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // Prefer the Xbox-format entry (UDATA/<titleId>/.../savegame.dat).
    ArchiveFile? entry;
    for (final f in archive) {
      if (f.name.toLowerCase().endsWith('savegame.dat') &&
          f.name.contains(kXboxTitleId)) {
        entry = f;
        break;
      }
    }

    // Fallback: any .dat file (e.g. the embedded base roster resource).
    if (entry == null) {
      for (final f in archive) {
        if (f.name.toLowerCase().endsWith('.dat')) {
          entry = f;
          break;
        }
      }
    }

    if (entry == null) {
      throw FormatException(
          'ZIP does not contain a savegame.dat under UDATA/$kXboxTitleId/ '
          'or any .dat file');
    }
    final dat = Uint8List.fromList(entry.content as List<int>);
    final save = NFL2K4Gamesave._(dat, _detectBase(dat));
    // Only track ZIP structure for Xbox saves (needed for re-save as ZIP).
    if (entry.name.contains(kXboxTitleId)) {
      save._zipArchive   = archive;
      save._zipEntryPath = entry.name;
    }
    return save;
  }

  /// True if this save has the Xbox VSAV magic or was loaded from a ZIP.
  /// PS2 saves return false and are written without signing.
  bool get isXbox =>
      (_data.length >= 4 &&
          _data[0] == 0x56 && _data[1] == 0x53 &&
          _data[2] == 0x41 && _data[3] == 0x56);

  /// Returns the gamesave bytes (.dat format), re-signing if this is an Xbox save.
  Uint8List toBytes({bool resign = true}) {
    if (resign && isXbox) _resign();
    return Uint8List.fromList(_data);
  }

  /// Returns the gamesave re-packed into the original ZIP structure.
  ///
  /// Throws [StateError] if this save was not loaded from a ZIP file.
  Uint8List toZipBytes({bool resign = true}) {
    if (_zipArchive == null || _zipEntryPath == null) {
      throw StateError(
          'Cannot produce ZIP bytes: this save was not loaded from a ZIP file.');
    }
    if (resign && isXbox) _resign();
    final out = Archive();
    for (final f in _zipArchive!) {
      if (f.name == _zipEntryPath) {
        out.addFile(ArchiveFile(f.name, _data.length, _data));
      } else {
        out.addFile(f);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }

  /// Loads the embedded 2K4 base roster.
  factory NFL2K4Gamesave.fromBaseRoster() =>
      NFL2K4Gamesave.fromBytes(kBase_roster);

  /// Opens a PS2 PSU or MAX save file.
  ///
  /// Extracts the main game-data file (the entry whose name starts with
  /// [kPs2TitleId]) and preserves all other entries (icon.sys, VIEW.ICO, …)
  /// so they survive a round-trip via [toPs2PsuBytes] / [toPs2MaxBytes].
  factory NFL2K4Gamesave.fromPs2Save(List<int> bytes) {
    final raw = Uint8List.fromList(bytes);
    final ps2Save = Ps2Save.fromBytes(raw);

    Uint8List? mainData;
    final sideFiles = <String, Uint8List>{};
    for (final file in ps2Save.files) {
      if (file.name.startsWith(kPs2TitleId)) {
        mainData = file.toBytes();
      } else {
        sideFiles[file.name] = file.toBytes();
      }
    }

    if (mainData == null) {
      throw FormatException(
          'PS2 save does not contain a $kPs2TitleId data file.');
    }

    final save = NFL2K4Gamesave._(mainData, _detectBase(mainData));
    save._ps2DirName = ps2Save.dirName;
    if (sideFiles.isNotEmpty) save._ps2SideFiles = sideFiles;
    return save;
  }

  /// Finds and opens the first NFL 2K4 save on a PS2 memory card image.
  factory NFL2K4Gamesave.fromPs2Card(List<int> cardImage) {
    final raw = Uint8List.fromList(cardImage);
    final card = Ps2Card.openMemory(raw);
    final saves = card.listSaves();
    final info = saves.firstWhere(
      (s) => s.dirName.startsWith(kPs2TitleId),
      orElse: () => throw FormatException(
          'No NFL 2K4 save ($kPs2TitleId*) found on PS2 memory card.'),
    );
    final psuBytes = card.exportSave(info.dirName);
    return NFL2K4Gamesave.fromPs2Save(psuBytes);
  }

  /// Finds and opens the first NFL 2K4 save on an Xbox Memory Unit image.
  factory NFL2K4Gamesave.fromXboxMU(List<int> muImage) {
    final raw = Uint8List.fromList(muImage);
    final mu = XboxMemoryUnit.fromBytes(raw);
    final matchingTitles =
        mu.titles.where((t) => t.id == kXboxTitleId).toList();
    if (matchingTitles.isEmpty || matchingTitles.first.saves.isEmpty) {
      throw FormatException(
          'No NFL 2K4 save (title $kXboxTitleId) found on Xbox Memory Unit.');
    }
    final zipBytes =
        Uint8List.fromList(matchingTitles.first.saves.first.exportZip());
    return NFL2K4Gamesave._fromZipBytes(zipBytes);
  }

  /// True if this save was loaded from a ZIP file.
  bool get isZip => _zipArchive != null;

  /// The file offset used as the GD base (0x18 for roster, 0x1E0 for franchise).
  int get base => _base;

  /// True if this is a franchise save (base = 0x1E0).
  /// True if this is a franchise save.
  ///
  /// Roster saves have ROST at offset 0x18 (Xbox) or 0x00 (PS2).
  /// Franchise saves have it at 0x1E0 (Xbox) or 0x1CC (PS2).
  bool get isFranchise => _base != kBase && _base != 0;

  // ---------------------------------------------------------------------------
  // Schedule (franchise only)
  // ---------------------------------------------------------------------------

  /// Reads the 17-week schedule from a franchise save.
  /// Each week contains exactly [kScheduleGamesPerWeek] slots; `null` = bye.
  /// Throws [StateError] if called on a roster save.
  List<List<ScheduleGame?>> getSchedule() {
    if (!isFranchise) throw StateError('Schedule is only available in franchise saves.');
    final weeks = <List<ScheduleGame?>>[];
    for (int w = 0; w < kScheduleWeeks; w++) {
      final weekOff = _base + kScheduleGd + w * (kScheduleGamesPerWeek + 1) * kScheduleGameStride;
      final games = <ScheduleGame?>[];
      for (int g = 0; g < kScheduleGamesPerWeek; g++) {
        final off = weekOff + g * kScheduleGameStride;
        if (off + kScheduleGameStride > _data.length) {
          games.add(null);
          continue;
        }
        final home  = _data[off];
        final away  = _data[off + 1];
        final month = _data[off + 2];
        final day   = _data[off + 3];
        final year  = _data[off + 4];
        final hour  = _data[off + 5];
        final min   = _data[off + 6];
        // Null slot: 8 zero bytes.
        if (home == 0 && away == 0 && month == 0 && day == 0) {
          games.add(null);
        } else {
          games.add(ScheduleGame(
            homeTeam: home, awayTeam: away,
            month: month, day: day, year: year, hour: hour, minute: min,
          ));
        }
      }
      weeks.add(games);
    }
    return weeks;
  }

  /// Writes [schedule] back into a franchise save.
  /// Each inner list must have exactly [kScheduleGamesPerWeek] entries.
  /// Throws [StateError] if called on a roster save.
  void setSchedule(List<List<ScheduleGame?>> schedule) {
    if (!isFranchise) throw StateError('Schedule is only available in franchise saves.');
    for (int w = 0; w < kScheduleWeeks && w < schedule.length; w++) {
      final weekOff = _base + kScheduleGd + w * (kScheduleGamesPerWeek + 1) * kScheduleGameStride;
      final games = schedule[w];

      // The last game slot (real or null) in the week gets flags=0x07.
      // All preceding game slots get flags=0x00.  The game engine uses this
      // to locate the week boundary within the 16 slots.
      final lastSlot = () {
        for (int g = kScheduleGamesPerWeek - 1; g >= 0; g--) {
          if (g < games.length && games[g] != null) return g;
        }
        return kScheduleGamesPerWeek - 1; // all null �� mark last slot
      }();

      for (int g = 0; g < kScheduleGamesPerWeek; g++) {
        final off = weekOff + g * kScheduleGameStride;
        if (off + kScheduleGameStride > _data.length) break;
        final game = g < games.length ? games[g] : null;
        final flags = g >= lastSlot ? 0x07 : 0x00;
        if (game == null) {
          for (int i = 0; i < kScheduleGameStride - 1; i++) { _data[off + i] = 0; }
          _data[off + 7] = flags;
        } else {
          _data[off]     = game.homeTeam;
          _data[off + 1] = game.awayTeam;
          _data[off + 2] = game.month;
          _data[off + 3] = game.day;
          _data[off + 4] = game.year;
          _data[off + 5] = game.hour;
          _data[off + 6] = game.minute;
          _data[off + 7] = flags;
        }
      }
      // Write null-game separator at slot 16.
      // The very last separator (week 17) carries flags=0x07 as the
      // end-of-schedule marker; all earlier separators are 8 zero bytes.
      final sepOff = weekOff + kScheduleGamesPerWeek * kScheduleGameStride;
      if (sepOff + kScheduleGameStride <= _data.length) {
        for (int i = 0; i < kScheduleGameStride - 1; i++) { _data[sepOff + i] = 0; }
        _data[sepOff + 7] = (w == kScheduleWeeks - 1) ? 0x07 : 0x00;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Team block
  // ---------------------------------------------------------------------------

  /// Returns all [PlayerRecord]s for the given team index (0–33).
  /// Team pointer → record_GD+4; subtract 4 to get true record start.
  List<PlayerRecord> getTeamPlayers(int teamIndex) {
    final blockFile = _base + kTeamBlockGd + teamIndex * kTeamStride;
    final players = <PlayerRecord>[];
    final seen = <int>{};  // resolved recFile offsets already added
    for (int slot = 0; slot < kTeamMaxPlayers; slot++) {
      final ptrFile = blockFile + slot * 4;
      if (ptrFile + 4 > _data.length) break;
      final bd = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
      final rel = bd.getInt32(0, Endian.little);
      if (rel == 0) break;
      // Resolve pointer
      final ptrGd = ptrFile - _base;
      final destGd = ptrGd + rel - 1;
      // Team pointers resolve to record_GD+4; subtract 4 for record start
      final recGd = destGd - 4;
      final recFile = _base + recGd;
      if (recGd < 0 || recFile < _base || recFile + 0x53 > _data.length) continue;
      // Skip stale pointers that resolve to an already-seen record.
      if (!seen.add(recFile)) continue;
      players.add(PlayerRecord(_data, recFile, _base));
    }
    return players;
  }

  /// Returns all roster players grouped by team, as a list of (teamName, players).
  /// Includes all 34 slots (32 NFL teams + FreeAgents + DraftClass).
  List<({String team, int teamIndex, List<PlayerRecord> players})>
      get allTeams {
    return [
      for (int i = 0; i < kTeamSlots; i++)
        (
          team: kTeamNames[i],
          teamIndex: i,
          players: getTeamPlayers(i),
        )
    ];
  }

  // ---------------------------------------------------------------------------
  // Free agent players
  // ---------------------------------------------------------------------------

  /// Returns all Free Agent player records from the dedicated FA pointer block
  /// at [kFABlockGd].  Same pointer format as team blocks (4-byte relative
  /// pointers, zero-terminated, target = record_GD+4).
  /// Confirmed present in both roster and franchise files.
  List<PlayerRecord> getFreeAgentPlayers() {
    final result = <PlayerRecord>[];
    for (int slot = 0; ; slot++) {
      final ptrFile = _base + kFABlockGd + slot * 4;
      if (ptrFile + 4 > _data.length) break;
      final bd = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
      final rel = bd.getInt32(0, Endian.little);
      if (rel == 0) break;
      final ptrGd  = ptrFile - _base;
      final destGd = ptrGd + rel - 1;
      final recGd  = destGd - 4;
      final recFile = _base + recGd;
      if (recGd < 0 || recFile < _base || recFile + 0x53 > _data.length) continue;
      result.add(PlayerRecord(_data, recFile, _base));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Player lookup
  // ---------------------------------------------------------------------------

  /// Find players by name (case-insensitive partial match on first or last name).
  /// Searches all team slots and the free-agent pool.
  List<({PlayerRecord player, String team, int teamIndex})> findPlayers(
      String query) {
    final q = query.toLowerCase();
    final results = <({PlayerRecord player, String team, int teamIndex})>[];
    // Search all known team slots first.
    for (int t = 0; t < kTeamSlots; t++) {
      for (final p in getTeamPlayers(t)) {
        try {
          final fn = p.firstName.toLowerCase();
          final ln = p.lastName.toLowerCase();
          if (fn.isEmpty && ln.isEmpty) continue;
          if (fn.contains(q) || ln.contains(q) || '$fn $ln'.contains(q)) {
            results.add((player: p, team: kTeamNames[t], teamIndex: t));
          }
        } catch (_) {
          continue;
        }
      }
    }
    // Also search free agents (unassigned players in the sequential array).
    for (final p in getFreeAgentPlayers()) {
      try {
        final fn = p.firstName.toLowerCase();
        final ln = p.lastName.toLowerCase();
        if (fn.isEmpty && ln.isEmpty) continue;
        if (fn.contains(q) || ln.contains(q) || '$fn $ln'.contains(q)) {
          results.add((player: p, team: 'Free Agents', teamIndex: -1));
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Team data
  // ---------------------------------------------------------------------------

  /// Cache: logo index → file offsets for the stadium/city strings.
  /// Built lazily by [_ensureStadiumCache].
  Map<int, ({int shortOff, int cityOff})>? _stadiumCache;

  /// Reads a UTF-16LE null-terminated string at the given absolute file offset.
  String _readUtf16(int fileOff) {
    final chars = <int>[];
    int off = fileOff;
    while (off + 1 < _data.length) {
      final lo = _data[off];
      final hi = _data[off + 1];
      if (lo == 0 && hi == 0) break;
      chars.add(lo | (hi << 8));
      off += 2;
    }
    return String.fromCharCodes(chars);
  }

  /// Returns the file offset of the string that follows the one at [fileOff].
  /// Advances past the null terminator and any subsequent zero-fill padding
  /// left by [_writeUtf16InPlace].
  int _nextUtf16(int fileOff) {
    int off = fileOff;
    while (off + 1 < _data.length) {
      final lo = _data[off];
      final hi = _data[off + 1];
      off += 2;
      if (lo == 0 && hi == 0) break;
    }
    // Skip zero-fill padding from shortened in-place writes.
    while (off + 1 < _data.length && _data[off] == 0 && _data[off + 1] == 0) {
      off += 2;
    }
    return off;
  }

  /// Writes [s] as UTF-16LE at [fileOff], zero-filling up to [maxChars]+1
  /// UTF-16 slots (string + null terminator).  Throws if [s] is longer than
  /// [maxChars] characters.
  void _writeUtf16InPlace(int fileOff, String s, int maxChars) {
    if (s.length > maxChars) {
      throw ArgumentError(
          'String too long: "${s}" (${s.length}) exceeds $maxChars chars');
    }
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      _data[fileOff + i * 2]     = c & 0xFF;
      _data[fileOff + i * 2 + 1] = c >> 8;
    }
    // Null terminator + zero-fill remainder.
    for (int i = s.length; i <= maxChars; i++) {
      _data[fileOff + i * 2]     = 0;
      _data[fileOff + i * 2 + 1] = 0;
    }
  }

  /// Returns the file offset of the Nickname UTF-16 string for [teamIndex]
  /// (must be 0–31; only NFL teams have entries in the nickname section).
  int _nicknameFileOff(int teamIndex) {
    int off = _base + kTeamNicknameSectionGd;
    for (int t = 0; t < teamIndex; t++) {
      off = _nextUtf16(off); // skip Nickname
      off = _nextUtf16(off); // skip Abbrev
    }
    return off;
  }

  /// Builds [_stadiumCache] on first call.
  void _ensureStadiumCache() {
    if (_stadiumCache != null) return;
    _stadiumCache = {};
    int off = _base + kTeamStadiumSectionGd;
    for (int i = 0; i < 40; i++) {
      if (off + 1 >= _data.length) break;
      final shortName = _readUtf16(off);
      if (shortName.isEmpty) break;
      final shortOff = off;
      off = _nextUtf16(off); // skip ShortStadium
      final cityOff = off;
      off = _nextUtf16(off); // skip City
      final sXX = _readUtf16(off);
      if (!sXX.startsWith('s')) break;
      final logoIdx = int.tryParse(sXX.substring(1));
      off = _nextUtf16(off); // skip "sXX"
      off = _nextUtf16(off); // skip LongStadium
      if (logoIdx != null) {
        _stadiumCache![logoIdx] = (shortOff: shortOff, cityOff: cityOff);
      }
    }
  }

  /// Returns the value of a team-level data field for the given [teamIndex].
  /// Supported fields: Nickname, Abbrev, Stadium, City, Logo, DefaultJersey.
  /// [teamIndex] must be 0–31 (NFL teams only).
  /// Returns the allocated character capacity of the UTF-16 slot at [fileOff]:
  /// the number of characters that can be written (not counting the null terminator).
  /// Computed as the distance to the next adjacent string divided by 2, minus 1.
  int _utf16SlotCapacity(int fileOff) =>
      (_nextUtf16(fileOff) - fileOff) ~/ 2 - 1;

  String getTeamField(int teamIndex, String field) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final blockFile = _base + kTeamBlockGd + teamIndex * kTeamStride;
    switch (field.toLowerCase()) {
      case 'nickname':
        return _readUtf16(_nicknameFileOff(teamIndex)).trim();
      case 'abbrev':
        final nickOff = _nicknameFileOff(teamIndex);
        return _readUtf16(_nextUtf16(nickOff)).trim();
      case 'logo':
        return _data[blockFile + kTeamLogoOffset].toString();
      case 'defaultjersey':
        return _data[blockFile + kTeamJerseyOffset].toString();
      case 'playbook':
        return getTeamPlaybook(teamIndex);
      case 'abbralt':
        return getTeamPlaybookAbbrev(teamIndex);
      case 'playercontrolled':
        return isFranchise ? (isTeamPlayerControlled(teamIndex) ? '1' : '0') : '0';
      case 'stadium':
        _ensureStadiumCache();
        final logoIdx = _data[blockFile + kTeamLogoOffset];
        final entry = _stadiumCache![logoIdx];
        if (entry == null) return '';
        return _readUtf16(entry.shortOff).trim();
      case 'city':
        final ptrGd = kTeamBlockGd + teamIndex * kTeamStride + 0x108;
        final val   = ByteData.sublistView(_data, _base + ptrGd, _base + ptrGd + 4)
                          .getInt32(0, Endian.little);
        return _readUtf16(_base + ptrGd + val - 1).trim();
      default:
        throw ArgumentError('Unknown team field: "$field"');
    }
  }

  /// Writes a team-level data field for the given [teamIndex].
  /// Supported fields: Nickname, Abbrev, Stadium, City, Logo, DefaultJersey.
  /// String fields may not exceed the original allocated character capacity.
  /// [teamIndex] must be 0–31 (NFL teams only).
  void setTeamField(int teamIndex, String field, String value) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    switch (field.toLowerCase()) {
      case 'nickname':
        final off = _nicknameFileOff(teamIndex);
        _writeUtf16InPlace(off, value, _utf16SlotCapacity(off));
      case 'abbrev':
        final nickOff = _nicknameFileOff(teamIndex);
        final abbrevOff = _nextUtf16(nickOff);
        _writeUtf16InPlace(abbrevOff, value, _utf16SlotCapacity(abbrevOff));
      case 'logo':
        // TODO: Logo/Stadium changes do not currently take effect in-game.
        // The logo byte is read, but the mechanism that maps it to a rendered
        // logo and displayed stadium is not yet fully understood.
        throw UnsupportedError('Setting "Logo" is not currently supported');
      case 'defaultjersey':
        throw UnsupportedError('Setting "DefaultJersey" is not currently supported');
      case 'stadium':
        // TODO: Logo/Stadium changes do not currently take effect in-game.
        // See 'logo' case above for details.
        throw UnsupportedError('Setting "Stadium" is not currently supported');
      case 'city':
        final ptrGd  = kTeamBlockGd + teamIndex * kTeamStride + 0x108;
        final val    = ByteData.sublistView(_data, _base + ptrGd, _base + ptrGd + 4)
                           .getInt32(0, Endian.little);
        final strOff = _base + ptrGd + val - 1;
        _writeUtf16InPlace(strOff, value, _utf16SlotCapacity(strOff));
      case 'playbook':
        setTeamPlaybook(teamIndex, value);
      case 'abbralt':
        setTeamPlaybookAbbrev(teamIndex, value);
      case 'playercontrolled':
        setTeamPlayerControlled(teamIndex, value.trim() == '1');
      case 'teamdata':
        break; // row-type tag — ignore on import
      default:
        throw ArgumentError('Unknown team field: "$field"');
    }
  }

  // ---------------------------------------------------------------------------
  // Playbook table
  // ---------------------------------------------------------------------------

  /// Cache: for each kPlaybookNames slot, the (nameGd, abbrevGd) string GDs.
  /// Built once at first access and never invalidated — team edits modify team
  /// slots but do not affect the canonical string addresses.
  List<({int nameGd, int abbrevGd})>? _pbEntries;
  /// Cache: playbook full-name string → kPlaybookNames index.
  Map<String, int>? _pbNameToIndex;
  /// Cache: playbook abbreviation string → kPlaybookNames index.
  Map<String, int>? _pbAbbrToIndex;

  void _ensurePlaybookCache() {
    if (_pbEntries != null) return;
    final entries    = <({int nameGd, int abbrevGd})>[];
    final nameToIdx  = <String, int>{};
    final abbrToIdx  = <String, int>{};
    for (int i = 0; i < kPlaybookNames.length; i++) {
      int resolveGd(int ptrOffset) {
        final pg  = kPlaybookTableGd + i * 8 + ptrOffset;
        final po  = _base + pg;
        final val = ByteData.sublistView(_data, po, po + 4).getInt32(0, Endian.little);
        return pg + val - 1;
      }
      final nameGd   = resolveGd(0);
      final abbrevGd = resolveGd(4);
      entries.add((nameGd: nameGd, abbrevGd: abbrevGd));
      nameToIdx[_readUtf16(_base + nameGd)]   = i;
      abbrToIdx[_readUtf16(_base + abbrevGd)] = i;
    }
    _pbEntries     = entries;
    _pbNameToIndex = nameToIdx;
    _pbAbbrToIndex = abbrToIdx;
  }

  /// Returns the [kPlaybookNames] token for [teamIndex]'s current playbook.
  /// [teamIndex] must be 0–31.
  String getTeamPlaybook(int teamIndex) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    _ensurePlaybookCache();
    final ptrGd  = kPlaybookTableGd + teamIndex * 8;
    final ptrOff = _base + ptrGd;
    final val    = ByteData.sublistView(_data, ptrOff, ptrOff + 4)
                       .getInt32(0, Endian.little);
    final destGd = ptrGd + val - 1;
    final name   = _readUtf16(_base + destGd);
    final idx    = _pbNameToIndex![name];
    if (idx == null) return name; // unknown — return raw string
    return kPlaybookNames[idx];
  }

  /// Sets [teamIndex]'s playbook to [pbToken] (a [kPlaybookNames] value).
  /// Updates both the name pointer and abbreviation pointer in the team's slot.
  /// [teamIndex] must be 0–31.
  void setTeamPlaybook(int teamIndex, String pbToken) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final srcIdx = kPlaybookNames.indexOf(pbToken);
    if (srcIdx < 0) {
      throw ArgumentError('Unknown playbook token: "$pbToken"');
    }
    _ensurePlaybookCache();

    // Use cached canonical GDs — never re-read from the (potentially modified) table.
    final entry = _pbEntries![srcIdx];

    void writePtr(int slotGd, int destGd) {
      final newVal = destGd - slotGd + 1;
      final off = _base + slotGd;
      ByteData.sublistView(_data, off, off + 4).setInt32(0, newVal, Endian.little);
    }

    writePtr(kPlaybookTableGd + teamIndex * 8,     entry.nameGd);
    writePtr(kPlaybookTableGd + teamIndex * 8 + 4, entry.abbrevGd);
  }

  /// Returns the team abbreviation string for [teamIndex] (e.g. "SF", "BUF").
  /// Reads from team block +0x110 (the team's own abbreviation pointer),
  /// which is independent of the current playbook selection.
  /// [teamIndex] must be 0–31.
  String getTeamPlaybookAbbrev(int teamIndex) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final ptrGd  = kTeamBlockGd + teamIndex * kTeamStride + 0x110;
    final ptrOff = _base + ptrGd;
    final val    = ByteData.sublistView(_data, ptrOff, ptrOff + 4)
                       .getInt32(0, Endian.little);
    final destGd = ptrGd + val - 1;
    return _readUtf16(_base + destGd).trim();
  }

  /// Sets the team abbreviation string for [teamIndex] in place.
  /// Writes directly to the string pointed to by team block +0x110.
  /// [teamIndex] must be 0–31.
  void setTeamPlaybookAbbrev(int teamIndex, String abbrev) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final ptrGd  = kTeamBlockGd + teamIndex * kTeamStride + 0x110;
    final ptrOff = _base + ptrGd;
    final val    = ByteData.sublistView(_data, ptrOff, ptrOff + 4)
                       .getInt32(0, Endian.little);
    final destGd = ptrGd + val - 1;
    final strOff = _base + destGd;
    _writeUtf16InPlace(strOff, abbrev, _utf16SlotCapacity(strOff));
  }

  // ---------------------------------------------------------------------------
  // Player-controlled team table (franchise only)
  // ---------------------------------------------------------------------------

  /// Returns true if [teamIndex] is set to player-controlled in this franchise.
  /// Throws [StateError] if called on a roster save.
  /// [teamIndex] must be 0–31.
  bool isTeamPlayerControlled(int teamIndex) {
    if (!isFranchise) throw StateError('isTeamPlayerControlled requires a franchise save');
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final off = _base + kTeamControlGd + teamIndex * kTeamControlStride;
    return _data[off] == 1;
  }

  /// Sets [teamIndex] to player-controlled (true) or CPU-controlled (false).
  /// Throws [StateError] if called on a roster save.
  /// [teamIndex] must be 0–31.
  void setTeamPlayerControlled(int teamIndex, bool value) {
    if (!isFranchise) throw StateError('setTeamPlayerControlled requires a franchise save');
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final off = _base + kTeamControlGd + teamIndex * kTeamControlStride;
    _data[off] = value ? 1 : 0;
  }

  /// Returns the abbreviations of all player-controlled teams (franchise only).
  /// Throws [StateError] if called on a roster save.
  List<String> getPlayerControlledTeams() {
    if (!isFranchise) throw StateError('getPlayerControlledTeams requires a franchise save');
    final result = <String>[];
    for (int t = 0; t < 32; t++) {
      if (isTeamPlayerControlled(t)) result.add(kTeamNames[t]);
    }
    return result;
  }

  /// Exports team-level data for all 32 NFL teams as a text block.
  ///
  /// Note: Stadium and Logo are intentionally excluded — writing those fields
  /// does not currently take effect in-game and the mechanism is not yet
  /// understood.  They remain readable via [getTeamField] for reference.
  ///
  /// For franchise saves, a `PlayerControlled` column (0/1) is appended.
  ///
  /// Format (roster):
  /// ```
  /// TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Playbook
  /// TeamData,49ers,49ers,SF,San Francisco,SF,PB_49ers
  /// ```
  /// Format (franchise):
  /// ```
  /// TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Playbook,PlayerControlled
  /// TeamData,49ers,49ers,SF,San Francisco,SF,PB_49ers,1
  /// ```
  String toTeamDataText() {
    final buf = StringBuffer();
    if (isFranchise) {
      buf.writeln('TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Playbook,PlayerControlled');
    } else {
      buf.writeln('TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Playbook');
    }
    for (int t = 0; t < 32; t++) {
      final team     = kTeamNames[t];
      final nick     = getTeamField(t, 'nickname');
      final abbrev   = getTeamField(t, 'abbrev');
      final city     = getTeamField(t, 'city');
      final abbrAlt  = getTeamPlaybookAbbrev(t);
      final playbook = getTeamPlaybook(t);
      final row = 'TeamData,${_csvQuote(team)},${_csvQuote(nick)},${_csvQuote(abbrev)},'
          '${_csvQuote(city)},$abbrAlt,$playbook';
      if (isFranchise) {
        buf.writeln('$row,${isTeamPlayerControlled(t) ? 1 : 0}');
      } else {
        buf.writeln(row);
      }
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Position-sort (post-apply depth-chart fix)
  // ---------------------------------------------------------------------------

  /// Reorders the team's players into canonical 2K4 position group order by
  /// physically writing each player's data to the slot the sorted order
  /// requires, leaving all team slot **pointers** unchanged.
  ///
  /// This is the franchise-safe sort: franchise saves store KR/PR slot indices
  /// and other positional references that break if the pointer array is
  /// reordered.  By writing player bytes to the fixed addresses the pointers
  /// already point to, the pointer array stays intact while the logical depth
  /// chart is reordered correctly.
  ///
  /// Uses a gather/bucket approach: players are walked in current slot order
  /// and appended to their position's bucket, preserving depth-chart order
  /// within each group.  Buckets are then drained in [_kPosOrder] sequence.
  /// All player data is exported as CSV rows **before** any writes so that
  /// in-place writes cannot corrupt later reads.
  ///
  /// [teamIndex] must be 0–31.
  void sortTeamPlayersByPosition(int teamIndex) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }

    // Snapshot current players in slot order.
    final players = <PlayerRecord>[];
    for (int slot = 0; slot < kTeamMaxPlayers; slot++) {
      final ptrFile =
          _base + kTeamBlockGd + teamIndex * kTeamStride + slot * 4;
      if (ptrFile + 4 > _data.length) break;
      final bd  = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
      final rel = bd.getInt32(0, Endian.little);
      if (rel == 0) break;
      final ptrGd   = ptrFile - _base;
      final destGd  = ptrGd + rel - 1;
      final recGd   = destGd - 4;
      final recFile = _base + recGd;
      if (recGd < 0 || recFile + 0x53 > _data.length) continue;
      players.add(PlayerRecord(_data, recFile, _base));
    }

    // Export every player to a full CSV row BEFORE any writes.
    final posIdx = RosterKey.all.fields
        .indexWhere((f) => f.toLowerCase() == 'position');
    final rows = [
      for (final p in players)
        RosterKey.all.fields.map((f) => _csvQuote(p.getAttribute(f))).join(',')
    ];

    // Bucket by position, preserving within-group order.
    final buckets = <String, List<String>>{};
    for (final row in rows) {
      final cols = _splitCsvLine(row);
      final pos = posIdx >= 0 && posIdx < cols.length
          ? cols[posIdx].trim()
          : '?';
      (buckets[pos] ??= []).add(row);
    }

    // Drain buckets in canonical order; unknown positions last.
    final ordered = <String>[];
    for (final pos in _kPosOrder) {
      ordered.addAll(buckets.remove(pos) ?? []);
    }
    for (final remaining in buckets.values) {
      ordered.addAll(remaining);
    }

    // ── HACK: shrink every player's name to a tiny unique placeholder before
    // writing sorted data.  insertPlayer writes names in-place; if an incoming
    // name is longer than the current occupant's name and the name section has
    // no zero-fill slack, the write throws.  Shrinking first (which always
    // succeeds — shorter names never need extra room) guarantees sufficient
    // space for the real names written in the loop below.
    // We use "f{i}"/"l{i}" (2–3 chars), always shorter than real NFL names.
    for (int i = 0; i < players.length; i++) {
      players[i].setAttribute('fname', 'f$i');
      players[i].setAttribute('lname', 'l$i');
    }

    // Write each sorted row to the slot's fixed physical address.
    for (int slot = 0; slot < ordered.length; slot++) {
      insertPlayer(teamIndex, slot, ordered[slot]);
    }
  }

  /// Calls [sortTeamPlayersByPosition] for all 32 NFL teams.
  void sortAllTeamsPlayersByPosition() {
    for (int t = 0; t < 32; t++) {
      sortTeamPlayersByPosition(t);
    }
  }

  /// For each team with invalid KR/PR slots, rotates the last available CBs
  /// into those slots, shifting the players between them up by one.
  ///
  /// Targets are processed largest-first so earlier rotations don't disturb
  /// CB positions still needed for later rotations.  CBs already satisfying
  /// a valid KR/PR slot are not used as candidates.
  void fixKrPrWithCbs() {
    for (int t = 0; t < 32; t++) {
      _fixTeamKrPrWithCbs(t);
    }
  }

  void _fixTeamKrPrWithCbs(int teamIndex) {
    // Read all non-zero slots as destGd values (0-indexed).
    final arr = <int>[];
    for (int slot = 0; slot < kTeamMaxPlayers; slot++) {
      final ptrFile = _base + kTeamBlockGd + teamIndex * kTeamStride + slot * 4;
      if (ptrFile + 4 > _data.length) break;
      final bd = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
      final rel = bd.getInt32(0, Endian.little);
      if (rel == 0) break;
      final ptrGd = ptrFile - _base;
      arr.add(ptrGd + rel - 1);
    }

    final slots = kTeamReturnerSlots[teamIndex];
    final allRoles = [
      (slot: slots.pr,  label: 'PR'),
      (slot: slots.kr1, label: 'KR1'),
      (slot: slots.kr2, label: 'KR2'),
    ].where((r) => r.slot != kNoReturnerSlot).toList();

    // Collect 0-indexed invalid targets.
    final invalidTargets = <int>[];
    for (final role in allRoles) {
      final idx = role.slot - 1;
      if (idx < 0 || idx >= arr.length) continue;
      final p = _playerFromDestGd(arr[idx]);
      if (p != null && !kValidReturnerPositions.contains(p.position)) {
        invalidTargets.add(idx);
      }
    }
    if (invalidTargets.isEmpty) return;

    // 0-indexed slots already satisfying a valid KR/PR role — don't disturb.
    final protectedSlots = <int>{};
    for (final role in allRoles) {
      final idx = role.slot - 1;
      if (idx < 0 || idx >= arr.length) continue;
      final p = _playerFromDestGd(arr[idx]);
      if (p != null && kValidReturnerPositions.contains(p.position)) {
        protectedSlots.add(idx);
      }
    }

    // Candidate CBs: CBs not in a protected slot, sorted ascending by index.
    final cbPositions = <int>[];
    for (int i = 0; i < arr.length; i++) {
      if (protectedSlots.contains(i)) continue;
      final p = _playerFromDestGd(arr[i]);
      if (p?.position == 'CB') cbPositions.add(i);
    }

    // Deduplicate targets (PR and KR1 often share the same slot index).
    // Then process largest-first so earlier rotations don't shift the indices
    // of CBs still needed for later rotations.
    final uniqueTargets = invalidTargets.toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    int cbIdx = cbPositions.length - 1;

    for (final target in uniqueTargets) {
      if (cbIdx < 0) break;
      final cbPos = cbPositions[cbIdx--];
      if (cbPos == target) continue;

      // Rotate arr[cbPos] → arr[target], shifting elements between left by one.
      // CB lands at the KR/PR slot; players between shift up one position.
      final val = arr[cbPos];
      for (int i = cbPos; i < target; i++) arr[i] = arr[i + 1];
      arr[target] = val;
    }

    // Write back with recalculated relative pointers.
    for (int slot = 0; slot < arr.length; slot++) {
      final ptrFile = _base + kTeamBlockGd + teamIndex * kTeamStride + slot * 4;
      final ptrGd   = ptrFile - _base;
      final newRel  = arr[slot] - ptrGd + 1;
      ByteData.sublistView(_data, ptrFile, ptrFile + 4)
          .setInt32(0, newRel, Endian.little);
    }
  }

  /// Builds a photo→skin and photo→face lookup from the embedded 2K4 base
  /// roster, then corrects any player in the current save whose [Skin] or
  /// [Face] doesn't match the base-roster reference for their [Photo].
  ///
  /// Players with Photo=0004 (no assigned photo) are skipped.
  /// Returns the number of players updated.
  int autoFixSkinFromPhoto() {
    final base = NFL2K4Gamesave.fromBaseRoster();

    // Build photo → (skin, face) map from every non-blank slot in the base roster.
    final skinMap = <String, String>{};
    final faceMap = <String, String>{};
    for (int slot = 0; slot < kMaxPlayerSlot; slot++) {
      final recFile = base._base + kPlayerStartGd + slot * kPlayerStride;
      if (recFile + 0x53 > base._data.length) break;
      final p = PlayerRecord(base._data, recFile, base._base);
      if (p.firstName.isEmpty && p.lastName.isEmpty) continue;
      final photo = p.getAttribute('photo');
      if (photo == '0004') continue;
      skinMap.putIfAbsent(photo, () => p.getAttribute('skin'));
      faceMap.putIfAbsent(photo, () => p.getAttribute('face'));
    }

    // Apply corrections to every non-blank slot in the current save.
    int updated = 0;
    for (int slot = 0; slot < kMaxPlayerSlot; slot++) {
      final recFile = _base + kPlayerStartGd + slot * kPlayerStride;
      if (recFile + 0x53 > _data.length) break;
      final p = PlayerRecord(_data, recFile, _base);
      if (p.firstName.isEmpty && p.lastName.isEmpty) continue;
      final photo = p.getAttribute('photo');
      if (photo == '0004') continue;
      final expectedSkin = skinMap[photo];
      final expectedFace = faceMap[photo];
      if (expectedSkin == null || expectedFace == null) continue;
      if (p.getAttribute('skin') != expectedSkin ||
          p.getAttribute('face') != expectedFace) {
        try {
          p.setAttribute('skin', expectedSkin);
          p.setAttribute('face', expectedFace);
          updated++;
        } catch (_) {
          // skip if the stored value is somehow out of range
        }
      }
    }
    return updated;
  }

  /// Updates every player's PBP field using the embedded ENFNameIndex lookup.
  ///
  /// Lookup order: 'LastName, FirstName' → 'LastName' → jersey number ('#NN').
  /// Players with an empty name are skipped.  Returns the number of players updated.
  int autoUpdatePBP() {
    int updated = 0;
    for (int slot = 0; slot < kMaxPlayerSlot; slot++) {
      final recFile = _base + kPlayerStartGd + slot * kPlayerStride;
      if (recFile + 0x53 > _data.length) break;
      final p = PlayerRecord(_data, recFile, _base);
      if (p.firstName.isEmpty && p.lastName.isEmpty) continue;

      final num = p.jerseyNumber;
      final number = num < 10 ? '#0$num' : '#$num';
      final key = '${p.lastName}, ${p.firstName}';

      String val;
      if (DataMap.PBPMap.containsKey(key))
        val = DataMap.PBPMap[key]!;
      else if (DataMap.PBPMap.containsKey(p.lastName))
        val = DataMap.PBPMap[p.lastName]!;
      else
        val = DataMap.PBPMap[number] ?? '';

      if (val.isNotEmpty) {
        p.pbp = int.parse(val);
        updated++;
      }
    }
    return updated;
  }

  /// Updates every player's Photo field using the embedded ENFPhotoIndex lookup.
  ///
  /// Looks up by 'LastName, FirstName'; falls back to the 'NoPhoto' entry (0004).
  /// Players with an empty name are skipped.  Returns the number of players updated.
  int autoUpdatePhoto() {
    int updated = 0;
    for (int slot = 0; slot < kMaxPlayerSlot; slot++) {
      final recFile = _base + kPlayerStartGd + slot * kPlayerStride;
      if (recFile + 0x53 > _data.length) break;
      final p = PlayerRecord(_data, recFile, _base);
      if (p.firstName.isEmpty && p.lastName.isEmpty) continue;

      final key = '${p.lastName}, ${p.firstName}';
      final val = DataMap.PhotoMap.containsKey(key)
          ? DataMap.PhotoMap[key]!
          : DataMap.PhotoMap['NoPhoto'] ?? '0000';

      p.photo = int.parse(val);
      updated++;
    }
    return updated;
  }

  /// TEMP DEBUG: Restores Mike Vrabel's data from the embedded base roster
  /// into his slot on the Patriots (team index 21) in the current save.
  ///
  /// Finds Vrabel by name in the base roster to get his CSV row, then locates
  /// his slot in the target save (by name match, falling back to the same slot
  /// index as in the base roster) and calls [insertPlayer].
  void vrabelFix() {
    
    String vrabelString = 
      "OLB,Mike,Vrabel,50,63,70,65,56,71,78,79,21,16,25,19,26,14,Power,11,10,10,85,10,"
      "13,80,86,60,5,53,72,60,Ohio State,8/14/1975,1349,1349,7,Right,261,6'4\",Normal,"
      "Skin1,Face12,No,Standard,FaceMask6,None,No,No,Taped,Team2,SingleBlack,SingleBlack,"
      "White,White,None,Shoe3,Shoe3,None,None,";

    insertPlayer(21, 33, vrabelString);
  }

  /// Resolves a destGd to a [PlayerRecord], or null if out of range.
  PlayerRecord? _playerFromDestGd(int destGd) {
    final recGd   = destGd - 4;
    final recFile = _base + recGd;
    if (recGd < 0 || recFile + 0x53 > _data.length) return null;
    return PlayerRecord(_data, recFile, _base);
  }

  /// Checks KR/PR slots for all 32 NFL teams and returns a list of warning
  /// lines for any slot whose player's position is not in [kValidReturnerPositions].
  /// Slots with value [kNoReturnerSlot] are silently skipped.
  List<String> checkKrPrPositions() {
    final warnings = <String>[];
    for (int t = 0; t < 32; t++) {
      final slots = kTeamReturnerSlots[t];
      final roles = [
        (label: 'PR',  slot: slots.pr),
        (label: 'KR1', slot: slots.kr1),
        (label: 'KR2', slot: slots.kr2),
      ];
      for (final role in roles) {
        if (role.slot == kNoReturnerSlot) continue;
        final player = _playerAtTeamSlot(t, role.slot);
        if (player == null) {
          warnings.add('${kTeamNames[t].padRight(12)} ${role.label}  slot=${role.slot}  (empty slot)');
          continue;
        }
        if (!kValidReturnerPositions.contains(player.position)) {
          warnings.add(
            '${kTeamNames[t].padRight(12)} ${role.label}  slot=${role.slot}'
            '  ${player.fullName}  ${player.position}  *** INVALID RETURNER ***',
          );
        }
      }
    }
    return warnings;
  }

  /// Returns the [PlayerRecord] at the given slot index within a team's pointer
  /// array, or null if the slot is empty or out of range.
  /// [slot] is 1-based (matching NFL2K4_KR_PR_slots.csv).
  PlayerRecord? _playerAtTeamSlot(int teamIndex, int slot) {
    final ptrFile = _base + kTeamBlockGd + teamIndex * kTeamStride + (slot - 1) * 4;
    if (ptrFile + 4 > _data.length) return null;
    final bd  = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
    final rel = bd.getInt32(0, Endian.little);
    if (rel == 0) return null;
    final ptrGd  = ptrFile - _base;
    final destGd = ptrGd + rel - 1;
    final recGd  = destGd - 4;
    final recFile = _base + recGd;
    if (recGd < 0 || recFile + 0x53 > _data.length) return null;
    return PlayerRecord(_data, recFile, _base);
  }

  /// Writes all player fields from [csvRow] (a comma-separated data row in
  /// [RosterKey.all] field order, no header line) directly to the physical
  /// player record that team slot [slotIndex] already points to.
  ///
  /// The team slot pointer is **never modified**.  This keeps the operation
  /// safe in franchise saves where other data structures reference players by
  /// slot index rather than by record address.
  ///
  /// `?` / `_` column values and empty columns are skipped (no-op for that
  /// field), matching [InputParser] sentinel behaviour.
  ///
  /// [teamIndex] must be 0–33; [slotIndex] is 0-based.
  void insertPlayer(int teamIndex, int slotIndex, String csvRow) {
    final ptrFile =
        _base + kTeamBlockGd + teamIndex * kTeamStride + slotIndex * 4;
    if (ptrFile + 4 > _data.length) {
      throw ArgumentError('Slot $slotIndex out of range for team $teamIndex');
    }
    final bd  = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
    final rel = bd.getInt32(0, Endian.little);
    if (rel == 0) {
      throw ArgumentError(
          'Slot $slotIndex for team $teamIndex is uninitialized (null pointer)');
    }
    final ptrGd   = ptrFile - _base;
    final destGd  = ptrGd + rel - 1;
    final recGd   = destGd - 4;
    final recFile = _base + recGd;
    if (recGd < 0 || recFile + 0x53 > _data.length) {
      throw ArgumentError(
          'Slot $slotIndex for team $teamIndex has an invalid pointer');
    }

    final player = PlayerRecord(_data, recFile, _base);
    final cols   = _splitCsvLine(csvRow);
    final fields = RosterKey.all.fields;

    for (int i = 0; i < fields.length && i < cols.length; i++) {
      final value = cols[i].trim();
      if (value == '?' || value == '_' || value.isEmpty) continue;
      player.setAttribute(fields[i], value);
    }
  }

  /// Canonical 2K4 position group order, matching the base roster layout.
  static const _kPosOrder = [
    'C', 'CB', 'DE', 'DT', 'FB', 'FS', 'G', 'RB',
    'ILB', 'K', 'OLB', 'P', 'QB', 'SS', 'T', 'TE', 'WR',
  ];

  // ---------------------------------------------------------------------------
  // Player name writing
  // ---------------------------------------------------------------------------

  /// Changes a player's first or last name in the string table.
  /// Delegates to [PlayerRecord.setAttribute] which handles all name-writing
  /// logic, including draft-class index detection and pointer adjustment.
  void setPlayerName(PlayerRecord player, String field, String newName) {
    player.setAttribute(field, newName);
  }

  // ---------------------------------------------------------------------------
  // Coach data
  // ---------------------------------------------------------------------------

  /// Offsets of the four string pointers within a coach record.
  static const List<int> _kCoachStringPtrOffsets = [0x00, 0x04, 0x34, 0x38, 0x3C, 0x40];

  /// Resolves the relative i32 LE pointer stored at [ptrFile] and returns the
  /// absolute file offset of the destination.
  int _resolveFilePtr(int ptrFile) {
    final rel = ByteData.sublistView(_data, ptrFile, ptrFile + 4)
        .getInt32(0, Endian.little);
    return ptrFile + rel - 1;
  }

  /// Shifts bytes [startFile+1 .. endFile-1] rightward by [amount] bytes.
  /// Bytes at [startFile .. startFile+amount-1] become available for overwrite.
  void _shiftCoachDataDown(int startFile, int amount, int endFile) {
    for (int i = endFile - 1; i > startFile; i--) {
      _data[i] = _data[i - amount];
    }
  }

  /// Shifts bytes [startFile .. endFile-1-amount] leftward by [amount] bytes,
  /// zero-filling the vacated tail [endFile-amount .. endFile-1].
  void _shiftCoachDataUp(int startFile, int amount, int endFile) {
    for (int i = startFile; i < endFile - amount; i++) {
      _data[i] = _data[i + amount];
    }
    for (int i = endFile - amount; i < endFile; i++) {
      _data[i] = 0;
    }
  }

  /// Adjusts every coach string pointer whose destination lies within
  /// [locationOfChange .. sectionEnd) by [delta] bytes.
  void _adjustCoachStringPointers(int locationOfChange, int delta) {
    if (delta == 0) return;
    final sectionEnd = _base + kCoachStringSectionEndGd;
    for (int t = 0; t < 32; t++) {
      final recFile = _base + kCoachRecordGd + t * kCoachStride;
      for (final off in _kCoachStringPtrOffsets) {
        final ptrFile = recFile + off;
        if (ptrFile + 4 > _data.length) continue;
        final bd = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
        final rel = bd.getInt32(0, Endian.little);
        final destFile = ptrFile + rel - 1;
        if (destFile >= locationOfChange && destFile < sectionEnd) {
          bd.setInt32(0, rel + delta, Endian.little);
        }
      }
    }
  }

  /// Writes [newValue] as the UTF-16LE string at the location pointed to by
  /// [recFile + ptrOffset], shifting the coach string section as needed.
  /// Throws [StateError] if the section has no room for a longer string.
  void _setCoachString(int recFile, int ptrOffset, String newValue) {
    final ptrFile = recFile + ptrOffset;
    final stringFile = _resolveFilePtr(ptrFile);
    final oldStr = _readUtf16(stringFile);
    final oldLen = oldStr.length;
    final newLen = newValue.length;
    final diff = 2 * (newLen - oldLen);  // byte change (+= grow, -= shrink)
    final sectionEnd = _base + kCoachStringSectionEndGd;

    if (diff != 0) {
      if (diff > 0) {
        // Verify unused slack at section tail.
        for (int i = sectionEnd - diff; i < sectionEnd; i++) {
          if (_data[i] != 0) {
            throw StateError(
                '_setCoachString: coach string section is full '
                '(need $diff more bytes)');
          }
        }
        _shiftCoachDataDown(stringFile, diff, sectionEnd);
      } else {
        _shiftCoachDataUp(stringFile, -diff, sectionEnd);
      }
      _adjustCoachStringPointers(stringFile + 2 * oldLen, diff);
    }

    // Write new string + null terminator at stringFile.
    for (int i = 0; i < newLen; i++) {
      _data[stringFile + i * 2]     = newValue.codeUnitAt(i) & 0xFF;
      _data[stringFile + i * 2 + 1] = newValue.codeUnitAt(i) >> 8;
    }
    _data[stringFile + newLen * 2]     = 0;
    _data[stringFile + newLen * 2 + 1] = 0;
  }

  /// Returns the value of a coach attribute for [teamIndex] (0–31).
  ///
  /// Supported fields: FirstName, LastName, Info1, Info2, Info3, Body, Photo,
  /// Wins, Losses, SeasonsWithTeam, TotalSeasons.
  /// Field names are case-insensitive.
  String getCoachAttribute(int teamIndex, String field) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final recFile = _base + kCoachRecordGd + teamIndex * kCoachStride;
    switch (field.toLowerCase()) {
      case 'firstname':
        return _readUtf16(_resolveFilePtr(recFile + 0x00));
      case 'lastname':
        return _readUtf16(_resolveFilePtr(recFile + 0x04));
      case 'info1':
        return _readUtf16(_resolveFilePtr(recFile + 0x34));
      case 'info2':
        return _readUtf16(_resolveFilePtr(recFile + 0x38));
      case 'info3':
        return _readUtf16(_resolveFilePtr(recFile + 0x3C));
      case 'body':
        final idx = _data[recFile + 0x0C];
        if (idx < kCoachBodyNames.length) return '[${kCoachBodyNames[idx]}]';
        return idx.toString(); // out-of-range fallback
      case 'photo':
        return ByteData.sublistView(_data, recFile + 0x44, recFile + 0x46)
            .getUint16(0, Endian.little).toString();
      case 'wins':
        return ByteData.sublistView(_data, recFile + 0x14, recFile + 0x16)
            .getUint16(0, Endian.little).toString();
      case 'losses':
        return ByteData.sublistView(_data, recFile + 0x16, recFile + 0x18)
            .getUint16(0, Endian.little).toString();
      case 'seasonswithteam':
        return ByteData.sublistView(_data, recFile + 0x10, recFile + 0x12)
            .getUint16(0, Endian.little).toString();
      case 'totalseasons':
        return ByteData.sublistView(_data, recFile + 0x12, recFile + 0x14)
            .getUint16(0, Endian.little).toString();
      default:
        throw ArgumentError('Unknown coach field: "$field"');
    }
  }

  /// Sets a coach attribute for [teamIndex] (0–31).
  ///
  /// Supported fields: FirstName, LastName, Info1, Info2, Info3, Body, Photo,
  /// Wins, Losses, SeasonsWithTeam, TotalSeasons.
  /// The row-type tags Coach and Team are silently ignored (useful on import).
  void setCoachAttribute(int teamIndex, String field, String value) {
    if (teamIndex < 0 || teamIndex >= 32) {
      throw RangeError.range(teamIndex, 0, 31, 'teamIndex');
    }
    final recFile = _base + kCoachRecordGd + teamIndex * kCoachStride;
    switch (field.toLowerCase()) {
      case 'firstname':
        _setCoachString(recFile, 0x00, value);
      case 'lastname':
        _setCoachString(recFile, 0x04, value);
      case 'info1':
        _setCoachString(recFile, 0x34, value);
      case 'info2':
        _setCoachString(recFile, 0x38, value);
      case 'info3':
        _setCoachString(recFile, 0x3C, value);
      case 'body':
        if (value.startsWith('[') && value.endsWith(']')) {
          final name = value.substring(1, value.length - 1);
          final bodyIdx = kCoachBodyNames.indexOf(name);
          if (bodyIdx < 0) {
            throw ArgumentError('Unknown coach body: "$value" — '
                'not in kCoachBodyNames');
          }
          _data[recFile + 0x0C] = bodyIdx;
        } else {
          // Raw numeric — accepted for backward compatibility.
          _data[recFile + 0x0C] = int.parse(value);
        }
      case 'photo':
        ByteData.sublistView(_data, recFile + 0x44, recFile + 0x46)
            .setUint16(0, int.parse(value), Endian.little);
      case 'wins':
        ByteData.sublistView(_data, recFile + 0x14, recFile + 0x16)
            .setUint16(0, int.parse(value), Endian.little);
      case 'losses':
        ByteData.sublistView(_data, recFile + 0x16, recFile + 0x18)
            .setUint16(0, int.parse(value), Endian.little);
      case 'seasonswithteam':
        ByteData.sublistView(_data, recFile + 0x10, recFile + 0x12)
            .setUint16(0, int.parse(value), Endian.little);
      case 'totalseasons':
        ByteData.sublistView(_data, recFile + 0x12, recFile + 0x14)
            .setUint16(0, int.parse(value), Endian.little);
      case 'coach':
      case 'team':
        break; // row-type/identity tags — silently ignored
      default:
        throw ArgumentError('Unknown coach field: "$field"');
    }
  }

  /// Exports coach data for all 32 NFL teams as a text block.
  ///
  /// Format:
  /// ```
  /// CoachKEY=Coach,Team,FirstName,LastName,Info1,Info2,Info3,Body,Photo,Wins,Losses,SeasonsWithTeam,TotalSeasons
  /// Coach,49ers,Dennis,Erickson,...
  /// ```
  String toCoachDataText() {
    final buf = StringBuffer();
    buf.writeln('CoachKEY=${kCoachKeyFields.join(',')}');
    for (int t = 0; t < 32; t++) {
      final team = kTeamNames[t];
      final row = kCoachKeyFields.map((f) {
        if (f == 'Coach') return 'Coach';
        if (f == 'Team') return _csvQuote(team);
        return _csvQuote(getCoachAttribute(t, f));
      }).join(',');
      buf.writeln(row);
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Text export
  // ---------------------------------------------------------------------------

  /// Exports player data as delimited text driven by [key].
  ///
  /// The first line is a `#` comment listing the key fields (treated as a
  /// comment by [InputParser], which auto-detects the key from it).
  /// Each team section is introduced by `Team = Name    Players:N`.
  ///
  /// [teamIndex] restricts output to one team; pass `-1` for Free Agents.
  /// [includeFreeAgents] appends a Free Agents section after all teams.
  /// [includeAllStarTeams] includes the 11 non-NFL slots (Challengers, Swamis,
  /// Alumni teams, All AFC/NFC/NFL) that live at indices 32–42.
  String toText(RosterKey key,
      {int? teamIndex,
      bool includeFreeAgents = false,
      bool includeAllStarTeams = false}) {
    final buf = StringBuffer();

    // # comment header — lists the key fields for human readability.
    buf.write('#');
    for (final f in key.fields) {
      buf.write('$f,');
    }
    buf.writeln();

    void writeSection(List<PlayerRecord> players, String teamName) {
      if (players.isEmpty) return;
      buf.writeln();
      buf.writeln('Team = $teamName    Players:${players.length}');
      for (final p in players) {
        for (final f in key.fields) {
          buf.write('${_csvQuote(p.getAttribute(f))},');
        }
        buf.writeln();
      }
    }

    if (teamIndex != null) {
      if (teamIndex == -1) {
        writeSection(getFreeAgentPlayers(), 'Free Agents');
      } else {
        writeSection(getTeamPlayers(teamIndex), kTeamNames[teamIndex]);
      }
    } else {
      final limit = includeAllStarTeams ? kTeamSlots : 32;
      for (int t = 0; t < limit; t++) {
        writeSection(getTeamPlayers(t), kTeamNames[t]);
      }
      if (includeFreeAgents) {
        writeSection(getFreeAgentPlayers(), 'Free Agents');
      }
    }
    return buf.toString();
  }

  /// Quotes a CSV field value if it contains a comma.
  static String _csvQuote(String s) {
    if (s.contains(',')) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  /// Splits a comma-delimited line using RFC-4180 quoting rules.
  static List<String> _splitCsvLine(String line) {
    final fields = <String>[];
    final cur = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else if (c == '"') {
          inQuotes = false;
        } else {
          cur.write(c);
        }
      } else if (c == ',') {
        fields.add(cur.toString());
        cur.clear();
      } else if (c == '"' && cur.isEmpty) {
        inQuotes = true;
      } else {
        cur.write(c);
      }
    }
    fields.add(cur.toString());
    return fields;
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  /// Returns the current byte buffer (modified in place by setters).
  Uint8List get bytes => _data;

  /// True when this save was loaded from a PS2 PSU or MAX container.
  bool get isPs2Container => _ps2DirName != null;

  // ---------------------------------------------------------------------------
  // PS2 container export
  // ---------------------------------------------------------------------------

  /// Returns this save packaged as a PS2 PSU file.
  ///
  /// Side files (icon.sys, VIEW.ICO, …) are included when they were preserved
  /// from the original PSU/MAX on load.
  Uint8List toPs2PsuBytes() => _toPs2Bytes(Ps2SaveFormat.psu);

  /// Returns this save packaged as a PS2 MAX (Action Replay Max) file.
  Uint8List toPs2MaxBytes() => _toPs2Bytes(Ps2SaveFormat.max);

  Uint8List _toPs2Bytes(Ps2SaveFormat format) {
    final dirName = _ps2DirName ?? _defaultPs2DirName;
    final fileMap = <String, Uint8List>{dirName: Uint8List.fromList(_data)};
    if (_ps2SideFiles != null) fileMap.addAll(_ps2SideFiles!);
    return Ps2Save.fromFiles(dirName, fileMap).toBytes(format: format);
  }

  /// The default PS2 directory/file name when the save was not loaded from
  /// a PS2 container (franchise vs. roster is inferred from [isFranchise]).
  String get _defaultPs2DirName =>
      isFranchise ? '${kPs2TitleId}BaseFran' : '${kPs2TitleId}BaseRos';

  /// Injects this save into a freshly formatted 8 MB PS2 memory card image.
  Uint8List toPs2CardBytes() {
    final card = Ps2Card.format();
    card.importSave(toPs2PsuBytes());
    return card.toBytes();
  }

  // ---------------------------------------------------------------------------
  // Xbox Memory Unit export
  // ---------------------------------------------------------------------------

  /// Injects this Xbox save into a freshly formatted Xbox Memory Unit image.
  ///
  /// Throws [StateError] if this is not an Xbox save ([isXbox] is false).
  Uint8List toXboxMUBytes() {
    if (!isXbox) {
      throw StateError(
          'Cannot create an Xbox Memory Unit from a non-Xbox save. '
          'Use toPs2CardBytes() for PS2 saves.');
    }
    final mu = XboxMemoryUnit.format();
    mu.importZip(_buildXboxZipBytes());
    return mu.bytes;
  }

  /// Builds a well-formed Xbox ZIP from the current save data.
  ///
  /// Uses the directory ID from the original ZIP when available; falls back to
  /// a fixed default so the result is always a valid FATX import.
  Uint8List _buildXboxZipBytes() {
    _resign();
    final dirId = _zipEntryPath != null
        ? _zipEntryPath!.split('/').elementAtOrNull(2) ?? 'A00000000001'
        : 'A00000000001';
    final subfolder = 'UDATA/$kXboxTitleId/$dirId';
    final archive = Archive();
    archive.addFile(
        ArchiveFile('$subfolder/savegame.dat', _data.length, _data));
    // Preserve all non-savegame entries from the original ZIP (e.g. metadata).
    if (_zipArchive != null) {
      for (final f in _zipArchive!) {
        if (f.name != _zipEntryPath && f.isFile) {
          archive.addFile(ArchiveFile(f.name, f.size, f.content as List<int>));
        }
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Re-signs the save using HMAC-SHA1 with the 2K4 Xbox key.
  ///
  /// The 20-byte signature lives at file bytes 4..23.
  /// We sign everything from byte 24 onward (the portion after the signature).
  /// Verified correct against both roster and franchise originals.
  void _resign() {
    final toSign = _data.sublist(kSignatureOffset + kSignatureLength);
    final hmac = Hmac(sha1, kXboxSignKey);
    final digest = hmac.convert(toSign);
    for (int i = 0; i < kSignatureLength; i++) {
      _data[kSignatureOffset + i] = digest.bytes[i];
    }
  }
}
