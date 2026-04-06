import 'dart:typed_data';
import 'constants.dart';

/// Represents a single player record in the 2K4 gamesave.
///
/// Holds a reference to the shared gamesave byte buffer and exposes
/// typed getters and setters for all confirmed player fields.
/// Setters modify the buffer in place — call [NFL2K4Gamesave.save] to persist.
class PlayerRecord {
  final Uint8List _data;
  final int _fileOffset; // file byte offset of record start
  final int _base;       // file offset of ROST magic (kBase for roster, 0x1E0 for franchise)

  PlayerRecord(this._data, this._fileOffset, [this._base = kBase]);

  // -------------------------------------------------------------------------
  // Raw helpers
  // -------------------------------------------------------------------------

  int _b(int off) => _data[_fileOffset + off];
  void _sb(int off, int v) => _data[_fileOffset + off] = v & 0xFF;

  int _u16(int off) => _b(off) | (_b(off + 1) << 8);
  void _su16(int off, int v) {
    _sb(off, v);
    _sb(off + 1, v >> 8);
  }

  int _resolvePtr(int off) {
    final ptrFileOff = _fileOffset + off;
    final bd = ByteData.sublistView(_data, ptrFileOff, ptrFileOff + 4);
    final rel = bd.getInt32(0, Endian.little);
    final ptrGd = ptrFileOff - _base;
    return ptrGd + rel - 1; // returns GD of destination
  }

  /// Returns the raw relative value stored at a name pointer slot (+0x10/+0x14).
  /// Values below 1000 indicate a name-index record (post-draft franchise rookie)
  /// rather than a real string-table pointer.
  int _rawNameRel(int off) {
    final ptrFileOff = _fileOffset + off;
    final bd = ByteData.sublistView(_data, ptrFileOff, ptrFileOff + 4);
    return bd.getInt32(0, Endian.little);
  }

  String _readUtf16Gd(int gd) {
    int off = _base + gd;
    if (off < 0 || off >= _data.length) return '';
    final sb = StringBuffer();
    while (off + 1 < _data.length) {
      final ch = _data[off] | (_data[off + 1] << 8);
      if (ch == 0) break;
      sb.writeCharCode(ch);
      off += 2;
    }
    return sb.toString();
  }

  String _readUtf16File(int fileOff) {
    final sb = StringBuffer();
    for (int i = fileOff; i + 1 < _data.length; i += 2) {
      final ch = _data[i] | (_data[i + 1] << 8);
      if (ch == 0) break;
      sb.writeCharCode(ch);
    }
    return sb.toString();
  }

  // -------------------------------------------------------------------------
  // Name section helpers
  // -------------------------------------------------------------------------

  int get _nameStart => _base + kNameSectionStartGd;
  int get _nameEnd   => _base + kNameSectionEndGd;

  int _namePtrDestFile(int ptrFileOff) {
    final bd = ByteData.sublistView(_data, ptrFileOff, ptrFileOff + 4);
    final rel = bd.getInt32(0, Endian.little);
    final ptrGd = ptrFileOff - _base;
    return _base + ptrGd + rel - 1;
  }

  void _adjustPointerAt(int ptrFileOff, int change) {
    final bd = ByteData.sublistView(_data, ptrFileOff, ptrFileOff + 4);
    bd.setInt32(0, bd.getInt32(0, Endian.little) + change, Endian.little);
  }

  void _shiftDown(int startIdx, int amount) {
    final end = _nameEnd;
    for (int i = end - 1; i > startIdx; i--) {
      _data[i] = _data[i - amount];
    }
  }

  void _shiftUp(int startIdx, int amount) {
    final end = _nameEnd;
    for (int i = startIdx; i < end - amount; i++) {
      _data[i] = _data[i + amount];
    }
    for (int i = end - amount; i < end; i++) {
      _data[i] = 0;
    }
  }

  void _adjustPlayerNamePointers(int changePoint, int diff) {
    if (diff == 0) return;
    for (int p = 0; p < kMaxPlayerSlot; p++) {
      final recFile = _base + kPlayerStartGd + p * kPlayerStride;
      if (recFile + 0x18 > _data.length) break;
      for (final ptrOff in [0x10, 0x14]) {
        final ptrFile = recFile + ptrOff;
        final bd = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
        final rel = bd.getInt32(0, Endian.little);
        if (rel < 1000) continue;
        final dest = _namePtrDestFile(ptrFile);
        if (dest >= changePoint && dest < _nameEnd) {
          _adjustPointerAt(ptrFile, diff);
        }
      }
    }
  }

  /// Writes [newName] into the string table for the name pointer at [ptrOff]
  /// (+0x10 for fname, +0x14 for lname).  Draft-class indices (rel < 1000)
  /// are silently skipped.  Throws [StateError] if there is insufficient zero
  /// slack to expand the name.
  void _writeName(int ptrOff, String newName) {
    final ptrFile = _fileOffset + ptrOff;
    final bd = ByteData.sublistView(_data, ptrFile, ptrFile + 4);
    final rel = bd.getInt32(0, Endian.little);
    if (rel < 1000) return; // draft-class name index, not a real pointer

    final destFile = _namePtrDestFile(ptrFile);
    if (destFile < _nameStart || destFile >= _nameEnd) return;

    final prevName = _readUtf16File(destFile);
    if (prevName == newName) return;

    final diff = 2 * (newName.length - prevName.length);

    if (diff > 0) {
      bool hasRoom = true;
      for (int i = _nameEnd - diff; i < _nameEnd; i++) {
        if (_data[i] != 0) { hasRoom = false; break; }
      }
      if (!hasRoom) {
        throw StateError(
            'Not enough space in name section to expand "$prevName" → "$newName" '
            '(need $diff more bytes).');
      }
      _shiftDown(destFile, diff);
    } else if (diff < 0) {
      _shiftUp(destFile, -diff);
    }

    _adjustPlayerNamePointers(destFile + 2 * prevName.length, diff);

    int w = destFile;
    for (int i = 0; i < newName.length; i++) {
      _data[w++] = newName.codeUnitAt(i);
      _data[w++] = 0;
    }
    _data[w++] = 0;
    _data[w]   = 0;
  }

  // -------------------------------------------------------------------------
  // Identity
  // -------------------------------------------------------------------------

  /// GD (game-data offset) of this record's start.
  int get gd => _fileOffset - _base;

  /// File offset of this record's start.
  int get fileOffset => _fileOffset;

  // -------------------------------------------------------------------------
  // College  (+0x04..+0x06, u24 LE, player-position-dependent encoding)
  // -------------------------------------------------------------------------

  /// Raw INI offset value for this player's college.
  /// Formula: u24LE(+0x04) − (kCollegeBase − slot × kPlayerStride)
  int get collegeINI {
    final slot = (_fileOffset - _base - kPlayerStartGd) ~/ kPlayerStride;
    final u24 = _b(0x04) | (_b(0x05) << 8) | (_b(0x06) << 16);
    return u24 - (kCollegeBase - slot * kPlayerStride);
  }

  /// College name string (from kCollegeByINI lookup).
  String get college => kCollegeByINI[collegeINI] ?? 'Unknown($collegeINI)';

  set college(String name) {
    final ini = kCollegeINI[name];
    if (ini == null) throw ArgumentError('Unknown college: $name');
    final slot = (_fileOffset - _base - kPlayerStartGd) ~/ kPlayerStride;
    final u24 = ini + kCollegeBase - slot * kPlayerStride;
    _sb(0x04, u24 & 0xFF);
    _sb(0x05, (u24 >> 8) & 0xFF);
    _sb(0x06, (u24 >> 16) & 0xFF);
  }

  /// First name (read from string table via pointer at +0x10).
  /// Post-draft franchise rookies store a name index (< 1000) instead of a
  /// real pointer; those are returned as 'n<index>' (e.g. 'n287').
  String get firstName {
    final rel = _rawNameRel(0x10);
    if (rel < 1000) return 'n$rel';
    return _readUtf16Gd(_resolvePtr(0x10));
  }

  /// Last name (read from string table via pointer at +0x14).
  /// See [firstName] for the name-index fallback.
  String get lastName {
    final rel = _rawNameRel(0x14);
    if (rel < 1000) return 'n$rel';
    return _readUtf16Gd(_resolvePtr(0x14));
  }

  String get fullName => '$firstName $lastName'.trim();

  // -------------------------------------------------------------------------
  // PBP / Photo  (+0x0A / +0x0C, u16 LE, same index space as 2K5)
  // -------------------------------------------------------------------------

  int get pbp => _u16(0x0A);
  set pbp(int v) => _su16(0x0A, v);

  int get photo => _u16(0x0C);
  set photo(int v) => _su16(0x0C, v);

  // -------------------------------------------------------------------------
  // Helmet / Shoes  (+0x0F)
  // bit6=Helmet, bits[5:3]=RightShoe, bits[2:0]=LeftShoe
  // -------------------------------------------------------------------------

  int get helmet => (_b(0x0F) >> 6) & 0x01;
  set helmet(int v) => _sb(0x0F, (_b(0x0F) & 0xBF) | ((v & 0x01) << 6));

  int get rightShoe => (_b(0x0F) >> 3) & 0x07;
  set rightShoe(int v) => _sb(0x0F, (_b(0x0F) & 0xC7) | ((v & 0x07) << 3));

  int get leftShoe => _b(0x0F) & 0x07;
  set leftShoe(int v) => _sb(0x0F, (_b(0x0F) & 0xF8) | (v & 0x07));

  // -------------------------------------------------------------------------
  // Appearance byte +0x18
  // bits[6:5]=Turtleneck, bits[4:3]=Body, bit2=EyeBlack, bit1=Hand, bit0=Dreads
  // -------------------------------------------------------------------------

  int get turtleneck => (_b(0x18) >> 5) & 0x03;
  set turtleneck(int v) => _sb(0x18, (_b(0x18) & 0x9F) | ((v & 0x03) << 5));

  int get body => (_b(0x18) >> 3) & 0x03;
  set body(int v) => _sb(0x18, (_b(0x18) & 0xE7) | ((v & 0x03) << 3));

  int get eyeBlack => (_b(0x18) >> 2) & 0x01;
  set eyeBlack(int v) => _sb(0x18, (_b(0x18) & 0xFB) | ((v & 0x01) << 2));

  /// 0=Left-handed, 1=Right-handed.
  int get hand => (_b(0x18) >> 1) & 0x01;
  set hand(int v) => _sb(0x18, (_b(0x18) & 0xFD) | ((v & 0x01) << 1));

  int get dreads => _b(0x18) & 0x01;
  set dreads(int v) => _sb(0x18, (_b(0x18) & 0xFE) | (v & 0x01));

  // -------------------------------------------------------------------------
  // Skin  (+0x19 bits[5:3])
  // 0=Lightest, 1=Light, 2=LightMedium, 3=DarkMedium, 4=Dark, 5=Darkest
  // -------------------------------------------------------------------------

  int get skin => (_b(0x19) >> 3) & 0x07;
  set skin(int v) => _sb(0x19, (_b(0x19) & 0xC7) | ((v & 0x07) << 3));

  // -------------------------------------------------------------------------
  // DOB  (+0x1A..+0x1B)
  // -------------------------------------------------------------------------

  /// Date of birth as (year, month, day).
  ({int year, int month, int day}) get dob {
    final b1 = _b(0x1A);
    final b2 = _b(0x1B);
    return (
      year: (b2 >> 1) + 1900,
      month: b1 & 0x0F,
      day: (b1 >> 4) | ((b2 & 0x01) << 4),
    );
  }

  set dob(({int year, int month, int day}) v) {
    _sb(0x1A, ((v.day & 0x0F) << 4) | (v.month & 0x0F));
    _sb(0x1B, ((v.year - 1900) << 1) | ((v.day >> 4) & 0x01));
  }

  /// ISO format for internal/storage use: YYYY-MM-DD
  String get dobString {
    final d = dob;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Display format matching 2K5 tool output: M/D/YYYY (no leading zeros)
  String get dobDisplayString {
    final d = dob;
    return '${d.month}/${d.day}/${d.year}';
  }

  // -------------------------------------------------------------------------
  // Equipment byte +0x1C  (MouthPiece / LeftGlove_high2 / NeckRoll / Sleeves)
  // bit5=MouthPiece, bits[7:6]=LeftGlove_high2, bits[4:2]=NeckRoll, bits[1:0]=Sleeves
  // -------------------------------------------------------------------------

  int get mouthPiece => (_b(0x1C) >> 5) & 0x01;
  set mouthPiece(int v) => _sb(0x1C, (_b(0x1C) & 0xDF) | ((v & 0x01) << 5));

  int get neckRoll => (_b(0x1C) >> 2) & 0x07;
  set neckRoll(int v) => _sb(0x1C, (_b(0x1C) & 0xE3) | ((v & 0x07) << 2));

  int get sleeves => _b(0x1C) & 0x03;
  set sleeves(int v) => _sb(0x1C, (_b(0x1C) & 0xFC) | (v & 0x03));

  // -------------------------------------------------------------------------
  // LeftGlove  (bits[7:6] of +0x1C and bits[1:0] of +0x1D — same as 2K5)
  // -------------------------------------------------------------------------

  int get leftGlove {
    final high2 = (_b(0x1C) >> 6) & 0x03;
    final low2 = _b(0x1D) & 0x03;
    return (high2 << 2) | low2;
  }

  set leftGlove(int v) {
    _sb(0x1C, (_b(0x1C) & 0x3F) | ((v >> 2) & 0x03) << 6);
    _sb(0x1D, (_b(0x1D) & 0xFC) | (v & 0x03));
  }

  // -------------------------------------------------------------------------
  // Equipment byte +0x1D  (RightGlove / LeftWrist_low2 / LeftGlove_low2)
  // bits[5:2]=RightGlove, bits[7:6]=LeftWrist_low2, bits[1:0]=LeftGlove_low2
  // -------------------------------------------------------------------------

  int get rightGlove => (_b(0x1D) >> 2) & 0x0F;
  set rightGlove(int v) => _sb(0x1D, (_b(0x1D) & 0xC3) | ((v & 0x0F) << 2));

  // -------------------------------------------------------------------------
  // LeftWrist  (bits[7:6] of +0x1D and bits[1:0] of +0x1E — same as 2K5)
  // -------------------------------------------------------------------------

  int get leftWrist {
    final combined = _b(0x1D) | (_b(0x1E) << 8);
    return (combined >> 6) & 0x0F;
  }

  set leftWrist(int v) {
    _sb(0x1D, (_b(0x1D) & 0x3F) | ((v & 0x03) << 6));
    _sb(0x1E, (_b(0x1E) & 0xFC) | ((v >> 2) & 0x03));
  }

  // -------------------------------------------------------------------------
  // RightWrist  (+0x1E bits[6:3] — shifted +1 from 2K5's bits[5:2])
  // -------------------------------------------------------------------------

  int get rightWrist => (_b(0x1E) >> 3) & 0x0F;
  set rightWrist(int v) => _sb(0x1E, (_b(0x1E) & 0x87) | ((v & 0x0F) << 3));

  // -------------------------------------------------------------------------
  // Elbows  (+0x1F )
  // bits[7:4]=RightElbow, bits[3:0]=LeftElbow
  // -------------------------------------------------------------------------

  int get leftElbow => _b(0x1F) & 0x0F;
  set leftElbow(int v) => _sb(0x1F, (_b(0x1F) & 0xF0) | (v & 0x0F));

  int get rightElbow => (_b(0x1F) >> 4) & 0x0F;
  set rightElbow(int v) => _sb(0x1F, (_b(0x1F) & 0x0F) | ((v & 0x0F) << 4));

  // -------------------------------------------------------------------------
  // JerseyNumber  (7-bit: bits[7:3] of +0x20 = low 5 bits; bits[1:0] of +0x21 = high 2 bits)
  // Same layout as 2K5.
  // -------------------------------------------------------------------------

  int get jerseyNumber =>
      ((_b(0x21) << 5) & 0x60) | ((_b(0x20) >> 3) & 0x1F);

  set jerseyNumber(int v) {
    _sb(0x20, (_b(0x20) & 0x07) | ((v & 0x1F) << 3));
    _sb(0x21, (_b(0x21) & 0xFC) | ((v >> 5) & 0x03));
  }

  // -------------------------------------------------------------------------
  // FaceMask  (+0x21 bits[6:2] — 5-bit value, same layout as 2K5)
  // -------------------------------------------------------------------------

  int get faceMask => (_b(0x21) & 0x7F) >> 2;
  set faceMask(int v) => _sb(0x21, (_b(0x21) & 0x83) | ((v & 0x1F) << 2));

  // -------------------------------------------------------------------------
  // Visor / FaceShield  (bit7 of +0x21, bit0 of +0x22)
  // 0=None, 1=Clear, 2=Black
  // Encoding: bit0 of value → +0x21 bit7; bit1 of value → +0x22 bit0
  // -------------------------------------------------------------------------

  int get visor => ((_b(0x22) & 0x01) << 1) | ((_b(0x21) >> 7) & 0x01);

  set visor(int v) {
    _sb(0x21, (_b(0x21) & 0x7F) | ((v & 0x01) << 7));
    _sb(0x22, (_b(0x22) & 0xFE) | ((v >> 1) & 0x01));
  }

  // -------------------------------------------------------------------------
  // Face  (+0x22 bits[4:1])
  // -------------------------------------------------------------------------

  int get face => (_b(0x22) >> 1) & 0x0F;
  set face(int v) => _sb(0x22, (_b(0x22) & 0xE1) | ((v & 0x0F) << 1));

  // -------------------------------------------------------------------------
  // Middle section
  // -------------------------------------------------------------------------

  /// Years as a pro (raw u8 at +0x27).
  int get yearsPro => _b(0x27);
  set yearsPro(int v) => _sb(0x27, v);

  /// Position index (0–16; see kPositionNames).
  int get positionIndex => _b(0x31);
  set positionIndex(int v) => _sb(0x31, v);

  String get position => positionIndex < kPositionNames.length
      ? kPositionNames[positionIndex]
      : '?($positionIndex)';

  set positionByName(String name) {
    final idx = kPositionNames.indexOf(name);
    if (idx < 0) throw ArgumentError('Unknown position: $name');
    positionIndex = idx;
  }

  /// Weight in lbs (stored as lbs − 150).
  int get weight => _b(0x32) + 150;
  set weight(int lbs) => _sb(0x32, lbs - 150);

  /// Height in inches (stored directly).
  int get height => _b(0x33);
  set height(int inches) => _sb(0x33, inches);

  String get heightString {
    final ft = height ~/ 12;
    final inches = height % 12;
    return "$ft'$inches\"";
  }

  // -------------------------------------------------------------------------
  // Ability bytes (+0x37..+0x52)
  // -------------------------------------------------------------------------

  /// Raw byte value of an ability (0–99). Use [getAbilityString] for output.
  int getAbility(String name) {
    final off = kAbilityOffsets[name];
    if (off == null) throw ArgumentError('Unknown ability: $name');
    return _b(off);
  }

  void setAbility(String name, int value) {
    final off = kAbilityOffsets[name];
    if (off == null) throw ArgumentError('Unknown ability: $name');
    _sb(off, value);
  }

  /// Returns the ability value as an output string.
  /// PowerRunStyle is rendered as 'Finesse'/'Balanced'/'Power'.
  String getAbilityString(String name) {
    final v = getAbility(name);
    if (name == 'PowerRunStyle') return powerRunStyleName(v);
    return v.toString();
  }

  Map<String, int> get abilities => {
    for (final entry in kAbilityOffsets.entries) entry.key: _b(entry.value)
  };

  // -------------------------------------------------------------------------
  // Generic get/set by field name (for CLI use)
  // -------------------------------------------------------------------------

  /// Get a field value as an output string (matches 2K5 tool format).
  String getAttribute(String field) {
    final abilityKey = _canonicalAbilityKey(field);
    if (abilityKey != null) return getAbilityString(abilityKey);
    switch (field.toLowerCase()) {
      case 'fname': return firstName;
      case 'lname': return lastName;
      case 'position': return position;
      case 'weight': return weight.toString();
      case 'height': return heightString;
      case 'yearspro': return yearsPro.toString();
      case 'jerseynumber': return jerseyNumber.toString();
      case 'pbp': return pbp.toString().padLeft(4, '0');
      case 'photo': return photo.toString().padLeft(4, '0');
      case 'dob': return dobDisplayString;
      case 'college': return college;
      case 'visor': return visor < kVisorNames.length ? kVisorNames[visor] : visor.toString();
      case 'bodytype': return body < kBodyNames.length ? kBodyNames[body] : body.toString();
      case 'skin': return 'Skin${skin + 1}';
      case 'hand': return kHandNames[hand & 1];
      case 'eyeblack': return kYesNoNames[eyeBlack & 1];
      case 'dreads': return kYesNoNames[dreads & 1];
      case 'helmet': return kHelmetNames[helmet & 1];
      case 'turtleneck': return turtleneck < kTurtleneckNames.length ? kTurtleneckNames[turtleneck] : turtleneck.toString();
      case 'sleeves': return sleeves < kSleevesNames.length ? kSleevesNames[sleeves] : sleeves.toString();
      case 'neckroll': return neckRoll < kNeckRollNames.length ? kNeckRollNames[neckRoll] : neckRoll.toString();
      case 'mouthpiece': return kYesNoNames[mouthPiece & 1];
      case 'leftglove': return leftGlove < kGloveNames.length ? kGloveNames[leftGlove] : leftGlove.toString();
      case 'rightglove': return rightGlove < kGloveNames.length ? kGloveNames[rightGlove] : rightGlove.toString();
      case 'leftwrist': return leftWrist < kWristNames.length ? kWristNames[leftWrist] : leftWrist.toString();
      case 'rightwrist': return rightWrist < kWristNames.length ? kWristNames[rightWrist] : rightWrist.toString();
      case 'leftelbow': return leftElbow < kElbowNames.length ? kElbowNames[leftElbow] : leftElbow.toString();
      case 'rightelbow': return rightElbow < kElbowNames.length ? kElbowNames[rightElbow] : rightElbow.toString();
      case 'leftshoe': return leftShoe < kShoeNames.length ? kShoeNames[leftShoe] : leftShoe.toString();
      case 'rightshoe': return rightShoe < kShoeNames.length ? kShoeNames[rightShoe] : rightShoe.toString();
      case 'facemask': return 'FaceMask${faceMask + 1}';
      case 'face':
        final f = face;
        return f < 15 ? 'Face${f + 1}' : f.toString();
      default:
        throw ArgumentError('Unknown field: $field');
    }
  }

  /// Set a field value from a string.
  /// Accepts the same value strings produced by [getAttribute].
  void setAttribute(String field, String value) {
    final abilityKey = _canonicalAbilityKey(field);
    if (abilityKey != null) {
      if (abilityKey == 'PowerRunStyle') {
        setAbility('PowerRunStyle', powerRunStyleValue(value));
      } else {
        setAbility(abilityKey, int.parse(value));
      }
      return;
    }
    switch (field.toLowerCase()) {
      case 'fname':
        // Draft-class name indices (e.g. 'n287') are read-only; skip them.
        if (!RegExp(r'^n\d+$').hasMatch(value)) _writeName(0x10, value);
      case 'lname':
        if (!RegExp(r'^n\d+$').hasMatch(value)) _writeName(0x14, value);
      case 'position':
        positionByName = value;
      case 'weight':
        weight = int.parse(value);
      case 'height':
        // Accept raw inches or "6'2\"" format
        if (value.contains("'")) {
          final parts = value.replaceAll('"', '').split("'");
          height = int.parse(parts[0]) * 12 + int.parse(parts[1]);
        } else {
          height = int.parse(value);
        }
      case 'yearspro':
        yearsPro = int.parse(value);
      case 'jerseynumber':
        jerseyNumber = int.parse(value);
      case 'pbp':
        pbp = int.parse(value);
      case 'photo':
        photo = int.parse(value);
      case 'bodytype':
        body = _parseEnum(value, kBodyNames, 'BodyType');
      case 'skin':
        // Accept "Skin3" (1-indexed) or raw index.
        // Values outside the 2K4 range (Skin1–Skin6) are mapped via mapSkin.
        final skinStr = value.toLowerCase().startsWith('skin')
            ? mapSkin(value)
            : value;
        skin = skinStr.toLowerCase().startsWith('skin')
            ? int.parse(skinStr.substring(4)) - 1
            : int.parse(skinStr);
      case 'hand':
        hand = _parseEnum(value, kHandNames, 'Hand');
      case 'eyeblack':
        eyeBlack = _parseEnum(value, kYesNoNames, 'EyeBlack');
      case 'dreads':
        dreads = _parseEnum(value, kYesNoNames, 'Dreads');
      case 'helmet':
        helmet = _parseEnum(value, kHelmetNames, 'Helmet');
      case 'turtleneck':
        turtleneck = _parseEnum(value, kTurtleneckNames, 'Turtleneck');
      case 'sleeves':
        sleeves = _parseEnum(value, kSleevesNames, 'Sleeves');
      case 'neckroll':
        neckRoll = _parseEnum(value, kNeckRollNames, 'NeckRoll');
      case 'mouthpiece':
        mouthPiece = _parseEnum(value, kYesNoNames, 'MouthPiece');
      case 'leftglove':
        leftGlove = _parseEnum(value, kGloveNames, 'LeftGlove');
      case 'rightglove':
        rightGlove = _parseEnum(value, kGloveNames, 'RightGlove');
      case 'leftwrist':
        leftWrist = _parseEnum(value, kWristNames, 'LeftWrist');
      case 'rightwrist':
        rightWrist = _parseEnum(value, kWristNames, 'RightWrist');
      case 'leftelbow':
        leftElbow = _parseEnum(value, kElbowNames, 'LeftElbow');
      case 'rightelbow':
        rightElbow = _parseEnum(value, kElbowNames, 'RightElbow');
      case 'leftshoe':
        leftShoe = _parseEnum(value, kShoeNames, 'LeftShoe');
      case 'rightshoe':
        rightShoe = _parseEnum(value, kShoeNames, 'RightShoe');
      case 'facemask':
        // Accept "FaceMask3" (1-indexed) or raw index
        faceMask = value.toLowerCase().startsWith('facemask')
            ? int.parse(value.substring(8)) - 1
            : int.parse(value) - 1;
      case 'face':
        // Accept "Face3" (1-indexed) or raw number.
        // Map out-of-range 2K5 values (raw 16–22) to 2K4 equivalents first.
        final fv = mapFace(value);
        face = fv.toLowerCase().startsWith('face')
            ? int.parse(fv.substring(4)) - 1
            : int.parse(fv);
      case 'dob':
        // Accept M/D/YYYY or YYYY-MM-DD
        if (value.contains('/')) {
          final parts = value.split('/');
          dob = (month: int.parse(parts[0]), day: int.parse(parts[1]), year: int.parse(parts[2]));
        } else {
          final parts = value.split('-');
          dob = (year: int.parse(parts[0]), month: int.parse(parts[1]), day: int.parse(parts[2]));
        }
      case 'college':
        // if it has a value in the 'kCollegeNormalize' Map, use it; otherwise use what we already have. 
        final normalized = kCollegeNormalize[value] ?? value;
        college = kCollegeINI.containsKey(normalized) ? normalized : 'None';
      case 'visor':
        visor = _parseEnum(value, kVisorNames, 'Visor');
      default:
        throw ArgumentError('Unknown or read-only field: $field');
    }
  }

  /// Returns the canonical (PascalCase) ability key for [field], or null if
  /// [field] is not an ability name.  The lookup is case-insensitive so that
  /// callers can pass 'speed', 'Speed', or 'SPEED' interchangeably.
  static String? _canonicalAbilityKey(String field) {
    if (kAbilityOffsets.containsKey(field)) return field;
    final lower = field.toLowerCase();
    for (final k in kAbilityOffsets.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    return null;
  }

  int _parseEnum(String value, List<String> names, String fieldName) {
    // Try name match first, then numeric fallback.
    // Accept any non-negative integer — getAttribute emits raw numbers for
    // out-of-range stored values, and we must be able to round-trip them.
    final idx = names.indexWhere((n) => n.toLowerCase() == value.toLowerCase());
    if (idx >= 0) return idx;
    final n = int.tryParse(value);
    if (n != null && n >= 0) return n;
    throw ArgumentError(
        'Invalid $fieldName value "$value". Valid: ${names.join(', ')}');
  }

  @override
  String toString() => '$fullName ($position) #$jerseyNumber';
}
