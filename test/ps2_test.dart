import 'dart:io';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'package:test/test.dart';
import 'test_helpers.dart';

const _ps2RosterPath      = 'test/test_files/BASLUS-20727BaseRos';
const _ps2FranchisePath   = 'test/test_files/BASLUS-20727BaseFran';
const _xboxRosterPath     = 'test/test_files/base_roster_2k4_savegame.dat';
const _xboxFranchisePath  = 'test/test_files/DefFran2K4_savegame.dat';
const _dataFile           = 'test/test_files/BaseNFL2K5Teams.ab.app.txt';

void main() {
  // ---------------------------------------------------------------------------
  // Platform detection
  // ---------------------------------------------------------------------------
  group('Platform detection (isXbox)', () {
    test('PS2 roster returns isXbox = false', () {
      final save = loadFile(_ps2RosterPath);
      expect(save.isXbox, isFalse);
    });

    test('PS2 franchise returns isXbox = false', () {
      final save = loadFile(_ps2FranchisePath);
      expect(save.isXbox, isFalse);
    });

    test('Xbox roster returns isXbox = true', () {
      final save = loadFile(_xboxRosterPath);
      expect(save.isXbox, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Base offset detection
  // ---------------------------------------------------------------------------
  group('Base offset detection', () {
    test('PS2 roster detects ROST at offset 0x00', () {
      final save = loadFile(_ps2RosterPath);
      expect(save.base, equals(0x00));
    });

    test('PS2 franchise detects ROST at offset 0x1CC', () {
      final save = loadFile(_ps2FranchisePath);
      expect(save.base, equals(0x1CC));
    });

    test('Xbox roster detects ROST at offset 0x18', () {
      final save = loadFile(_xboxRosterPath);
      expect(save.base, equals(0x18));
    });
  });

  // ---------------------------------------------------------------------------
  // toBytes() does not re-sign PS2 saves
  // ---------------------------------------------------------------------------
  group('PS2 save — no signing on output', () {
    test('toBytes() output does not start with VSAV magic', () {
      final save   = loadFile(_ps2RosterPath);
      final bytes  = save.toBytes();
      // VSAV: 56 53 41 56
      expect(bytes[0], isNot(equals(0x56)));
      expect(
        bytes.sublist(0, 4),
        isNot(equals([0x56, 0x53, 0x41, 0x56])),
      );
    });

    test('toBytes() output starts with ROST magic for PS2 roster', () {
      final save  = loadFile(_ps2RosterPath);
      final bytes = save.toBytes();
      // ROST: 52 4F 53 54
      expect(bytes.sublist(0, 4), equals([0x52, 0x4F, 0x53, 0x54]));
    });

    test('toBytes() output size matches original PS2 file', () {
      final save        = loadFile(_ps2RosterPath);
      final originalLen = File(_ps2RosterPath).readAsBytesSync().length;
      expect(save.toBytes().length, equals(originalLen));
    });
  });

  // ---------------------------------------------------------------------------
  // Apply BaseNFL2K5Teams data to PS2 roster
  // ---------------------------------------------------------------------------
  group('Apply BaseNFL2K5Teams.ab.app.txt to PS2 roster', () {
    late NFL2K4Gamesave save;
    late ApplyResult result;

    setUp(() {
      save   = loadFile(_ps2RosterPath);
      final text = File(_dataFile).readAsStringSync();
      result = InputParser(save).applyText(text, key: RosterKey.all);
    });

    test('applies with no errors', () {
      expect(result.errors, isEmpty);
    });

    test('updates players across all 32 teams', () {
      expect(result.updated, greaterThan(1500));
    });

    test('49ers QB Tim Rattay — abilities applied correctly', () {
      final niners = save.getTeamPlayers(kTeamNames.indexOf('49ers'));
      final rattay = niners.firstWhere(
        (p) => p.getAttribute('lname') == 'Rattay',
      );
      expect(rattay.getAttribute('PassAccuracy'),  equals('78'));
      expect(rattay.getAttribute('PassArmStrength'), equals('75'));
      expect(rattay.getAttribute('Speed'),         equals('64'));
    });

    test('49ers CB Ahmed Plummer — appearance applied correctly', () {
      final niners  = save.getTeamPlayers(kTeamNames.indexOf('49ers'));
      final plummer = niners.firstWhere(
        (p) => p.getAttribute('lname') == 'Plummer',
      );
      expect(plummer.getAttribute('Speed'),    equals('90'));
      expect(plummer.getAttribute('BodyType'), equals('Normal'));
      expect(plummer.getAttribute('Skin'),     equals('Skin3'));
      expect(plummer.getAttribute('Face'),     equals('Face1'));
    });

    test('Eagles CB Sheldon Brown — abilities applied correctly', () {
      final eagles = save.getTeamPlayers(kTeamNames.indexOf('Eagles'));
      final brown  = eagles.firstWhere(
        (p) => p.getAttribute('lname') == 'Brown',
      );
      expect(brown.getAttribute('Speed'),    equals('91'));
      expect(brown.getAttribute('Coverage'), equals('75'));
    });
  });

  // ---------------------------------------------------------------------------
  // Round-trip: load PS2 → apply → toBytes → reload → verify
  // ---------------------------------------------------------------------------
  group('PS2 roster round-trip', () {
    test('data survives toBytes() → fromBytes() cycle', () {
      final save1 = loadFile(_ps2RosterPath);
      final text  = File(_dataFile).readAsStringSync();
      InputParser(save1).applyText(text, key: RosterKey.all);

      final save2 = NFL2K4Gamesave.fromBytes(save1.toBytes());

      // Spot-check a player survives the round-trip
      final niners1 = save1.getTeamPlayers(kTeamNames.indexOf('49ers'));
      final niners2 = save2.getTeamPlayers(kTeamNames.indexOf('49ers'));
      expect(niners2.length, equals(niners1.length));

      final rattay1 = niners1.firstWhere((p) => p.getAttribute('lname') == 'Rattay');
      final rattay2 = niners2.firstWhere((p) => p.getAttribute('lname') == 'Rattay');
      expect(
        rattay2.getAttribute('PassAccuracy'),
        equals(rattay1.getAttribute('PassAccuracy')),
      );
    });

    test('round-tripped save is still detected as PS2 (isXbox = false)', () {
      final save1 = loadFile(_ps2RosterPath);
      final save2 = NFL2K4Gamesave.fromBytes(save1.toBytes());
      expect(save2.isXbox, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Xbox → PS2 conversion
  // ---------------------------------------------------------------------------
  group('Xbox → PS2 conversion', () {
    late NFL2K4Gamesave xboxSave;

    setUp(() {
      xboxSave = loadFile(_xboxRosterPath);
    });

    NFL2K4Gamesave _reloadPsu() =>
        NFL2K4Gamesave.fromPs2Save(xboxSave.toPs2PsuBytes());

    NFL2K4Gamesave _reloadMax() =>
        NFL2K4Gamesave.fromPs2Save(xboxSave.toPs2MaxBytes());

    test('PSU: reloaded save is not Xbox', () {
      expect(_reloadPsu().isXbox, isFalse);
    });

    test('PSU: reloaded save has ROST at offset 0x00', () {
      expect(_reloadPsu().base, equals(0x00));
    });

    test('PSU: raw data does not start with VSAV magic', () {
      final bytes = _reloadPsu().toBytes();
      expect(bytes.sublist(0, 4), isNot(equals([0x56, 0x53, 0x41, 0x56])));
    });

    test('PSU: raw data starts with ROST magic', () {
      final bytes = _reloadPsu().toBytes();
      expect(bytes.sublist(0, 4), equals([0x52, 0x4F, 0x53, 0x54]));
    });

    test('MAX: reloaded save is not Xbox', () {
      expect(_reloadMax().isXbox, isFalse);
    });

    test('MAX: reloaded save has ROST at offset 0x00', () {
      expect(_reloadMax().base, equals(0x00));
    });

    test('MAX: raw data starts with ROST magic', () {
      final bytes = _reloadMax().toBytes();
      expect(bytes.sublist(0, 4), equals([0x52, 0x4F, 0x53, 0x54]));
    });

    test('player data is preserved across all 32 teams', () {
      final ps2Save = _reloadPsu();
      for (int t = 0; t < 32; t++) {
        final xboxPlayers = xboxSave.getTeamPlayers(t);
        final ps2Players  = ps2Save.getTeamPlayers(t);
        expect(ps2Players.length, equals(xboxPlayers.length),
            reason: '${kTeamNames[t]} player count differs');
        for (int i = 0; i < xboxPlayers.length; i++) {
          expect(
            ps2Players[i].getAttribute('Speed'),
            equals(xboxPlayers[i].getAttribute('Speed')),
            reason: '${kTeamNames[t]} player $i Speed differs',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Xbox franchise → PS2 conversion
  // ---------------------------------------------------------------------------
  group('Xbox franchise → PS2 conversion', () {
    late NFL2K4Gamesave xboxFran;

    setUp(() {
      xboxFran = loadFile(_xboxFranchisePath);
    });

    test('Xbox franchise is detected as franchise', () {
      expect(xboxFran.isFranchise, isTrue);
    });

    test('PSU: reloaded franchise is not Xbox', () {
      final ps2 = NFL2K4Gamesave.fromPs2Save(xboxFran.toPs2PsuBytes());
      expect(ps2.isXbox, isFalse);
    });

    test('PSU: reloaded franchise is still a franchise save', () {
      final ps2 = NFL2K4Gamesave.fromPs2Save(xboxFran.toPs2PsuBytes());
      expect(ps2.isFranchise, isTrue);
    });

    test('PSU: franchise ROST is at PS2-native offset 0x1CC', () {
      final ps2 = NFL2K4Gamesave.fromPs2Save(xboxFran.toPs2PsuBytes());
      expect(ps2.base, equals(0x1CC));
    });

    test('PSU: franchise player data is preserved across all 32 teams', () {
      final ps2 = NFL2K4Gamesave.fromPs2Save(xboxFran.toPs2PsuBytes());
      for (int t = 0; t < 32; t++) {
        final xPlayers   = xboxFran.getTeamPlayers(t);
        final ps2Players = ps2.getTeamPlayers(t);
        expect(ps2Players.length, equals(xPlayers.length),
            reason: '${kTeamNames[t]} player count differs');
        for (int i = 0; i < xPlayers.length; i++) {
          expect(
            ps2Players[i].getAttribute('Speed'),
            equals(xPlayers[i].getAttribute('Speed')),
            reason: '${kTeamNames[t]} player $i Speed differs',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PS2 and Xbox base rosters read the same player data
  // ---------------------------------------------------------------------------
  group('PS2 vs Xbox base roster — player data matches', () {
    test('49ers player count matches between platforms', () {
      final ps2  = loadFile(_ps2RosterPath);
      final xbox = loadFile(_xboxRosterPath);
      expect(
        ps2.getTeamPlayers(kTeamNames.indexOf('49ers')).length,
        equals(xbox.getTeamPlayers(kTeamNames.indexOf('49ers')).length),
      );
    });

    test('all 32 teams have identical Speed values across platforms', () {
      final ps2  = loadFile(_ps2RosterPath);
      final xbox = loadFile(_xboxRosterPath);

      for (int t = 0; t < 32; t++) {
        final ps2Players  = ps2.getTeamPlayers(t);
        final xboxPlayers = xbox.getTeamPlayers(t);
        expect(ps2Players.length, equals(xboxPlayers.length),
            reason: '${kTeamNames[t]} player count differs');
        for (int i = 0; i < ps2Players.length; i++) {
          expect(
            ps2Players[i].getAttribute('Speed'),
            equals(xboxPlayers[i].getAttribute('Speed')),
            reason: '${kTeamNames[t]} player $i Speed differs',
          );
        }
      }
    });
  });
}
