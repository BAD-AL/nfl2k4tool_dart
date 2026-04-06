import 'dart:io';
import 'package:dart_mymc/dart_mymc.dart' show Ps2Card;
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'package:test/test.dart';

const _psuPath    = 'test/test_files/BASLUS-20727BaseRos.psu';
const _maxPath    = 'test/test_files/BASLUS-20727BaseRos.max';
const _ps2Card    = 'test/test_files/BaseRoster.ps2';
const _xboxMU     = 'test/test_files/NFL24Fran.img';
const _rawPs2Ros  = 'test/test_files/BASLUS-20727BaseRos';
const _xboxZip    = 'test/test_files/NFL24Fran.zip';

void main() {
  // ---------------------------------------------------------------------------
  // PSU — format detection
  // ---------------------------------------------------------------------------
  group('PSU — format detection', () {
    late NFL2K4Gamesave save;
    setUpAll(() =>
        save = NFL2K4Gamesave.fromPs2Save(File(_psuPath).readAsBytesSync()));

    test('loads without error',       () => expect(save, isNotNull));
    test('isXbox = false',            () => expect(save.isXbox, isFalse));
    test('isPs2Container = true',     () => expect(save.isPs2Container, isTrue));
    test('isFranchise = false',       () => expect(save.isFranchise, isFalse));
    test('ROST detected at offset 0', () => expect(save.base, equals(0x00)));
  });

  // ---------------------------------------------------------------------------
  // MAX — format detection
  // ---------------------------------------------------------------------------
  group('MAX — format detection', () {
    late NFL2K4Gamesave save;
    setUpAll(() =>
        save = NFL2K4Gamesave.fromPs2Save(File(_maxPath).readAsBytesSync()));

    test('loads without error',       () => expect(save, isNotNull));
    test('isXbox = false',            () => expect(save.isXbox, isFalse));
    test('isPs2Container = true',     () => expect(save.isPs2Container, isTrue));
    test('isFranchise = false',       () => expect(save.isFranchise, isFalse));
    test('ROST detected at offset 0', () => expect(save.base, equals(0x00)));
  });

  // ---------------------------------------------------------------------------
  // PS2 memory card — format detection
  // ---------------------------------------------------------------------------
  group('PS2 memory card — format detection', () {
    late NFL2K4Gamesave save;
    setUpAll(() =>
        save = NFL2K4Gamesave.fromPs2Card(File(_ps2Card).readAsBytesSync()));

    test('loads without error',       () => expect(save, isNotNull));
    test('isXbox = false',            () => expect(save.isXbox, isFalse));
    test('isPs2Container = true',     () => expect(save.isPs2Container, isTrue));
    test('isFranchise = false',       () => expect(save.isFranchise, isFalse));
    test('ROST detected at offset 0', () => expect(save.base, equals(0x00)));
  });

  // ---------------------------------------------------------------------------
  // Xbox Memory Unit — format detection
  // ---------------------------------------------------------------------------
  group('Xbox Memory Unit — format detection', () {
    late NFL2K4Gamesave save;
    setUpAll(() =>
        save = NFL2K4Gamesave.fromXboxMU(File(_xboxMU).readAsBytesSync()));

    test('loads without error',       () => expect(save, isNotNull));
    test('isXbox = true',             () => expect(save.isXbox, isTrue));
    test('isPs2Container = false',    () => expect(save.isPs2Container, isFalse));
    test('isFranchise = true',        () => expect(save.isFranchise, isTrue));
  });

  // ---------------------------------------------------------------------------
  // PSU vs MAX — same underlying save
  // ---------------------------------------------------------------------------
  group('PSU vs MAX — data parity', () {
    late NFL2K4Gamesave psu;
    late NFL2K4Gamesave max;
    setUpAll(() {
      psu = NFL2K4Gamesave.fromPs2Save(File(_psuPath).readAsBytesSync());
      max = NFL2K4Gamesave.fromPs2Save(File(_maxPath).readAsBytesSync());
    });

    test('all 32 teams have equal player counts', () {
      for (int t = 0; t < 32; t++) {
        expect(max.getTeamPlayers(t).length,
            equals(psu.getTeamPlayers(t).length),
            reason: kTeamNames[t]);
      }
    });

    test('all 32 teams have identical Speed values', () {
      for (int t = 0; t < 32; t++) {
        final psuPlayers = psu.getTeamPlayers(t);
        final maxPlayers = max.getTeamPlayers(t);
        for (int i = 0; i < psuPlayers.length; i++) {
          expect(maxPlayers[i].getAttribute('Speed'),
              equals(psuPlayers[i].getAttribute('Speed')),
              reason: '${kTeamNames[t]} player $i');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PSU vs raw PS2 file — same underlying save, different containers
  // ---------------------------------------------------------------------------
  group('PSU vs raw PS2 — data parity', () {
    late NFL2K4Gamesave psu;
    late NFL2K4Gamesave raw;
    setUpAll(() {
      psu = NFL2K4Gamesave.fromPs2Save(File(_psuPath).readAsBytesSync());
      raw = NFL2K4Gamesave.fromBytes(File(_rawPs2Ros).readAsBytesSync());
    });

    test('all 32 teams have equal player counts', () {
      for (int t = 0; t < 32; t++) {
        expect(psu.getTeamPlayers(t).length,
            equals(raw.getTeamPlayers(t).length),
            reason: kTeamNames[t]);
      }
    });

    test('all 32 teams have identical Speed values', () {
      for (int t = 0; t < 32; t++) {
        final psuPlayers = psu.getTeamPlayers(t);
        final rawPlayers = raw.getTeamPlayers(t);
        for (int i = 0; i < psuPlayers.length; i++) {
          expect(psuPlayers[i].getAttribute('Speed'),
              equals(rawPlayers[i].getAttribute('Speed')),
              reason: '${kTeamNames[t]} player $i');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Xbox MU vs ZIP — same underlying save, different containers
  // ---------------------------------------------------------------------------
  group('Xbox MU vs ZIP — data parity', () {
    late NFL2K4Gamesave mu;
    late NFL2K4Gamesave zip;
    setUpAll(() {
      mu  = NFL2K4Gamesave.fromXboxMU(File(_xboxMU).readAsBytesSync());
      zip = NFL2K4Gamesave.fromBytes(File(_xboxZip).readAsBytesSync());
    });

    test('all 32 teams have equal player counts', () {
      for (int t = 0; t < 32; t++) {
        expect(mu.getTeamPlayers(t).length,
            equals(zip.getTeamPlayers(t).length),
            reason: kTeamNames[t]);
      }
    });

    test('all 32 teams have identical Speed values', () {
      for (int t = 0; t < 32; t++) {
        final muPlayers  = mu.getTeamPlayers(t);
        final zipPlayers = zip.getTeamPlayers(t);
        for (int i = 0; i < muPlayers.length; i++) {
          expect(muPlayers[i].getAttribute('Speed'),
              equals(zipPlayers[i].getAttribute('Speed')),
              reason: '${kTeamNames[t]} player $i');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PSU round-trip
  // ---------------------------------------------------------------------------
  group('PSU round-trip — toPs2PsuBytes() → fromPs2Save()', () {
    late NFL2K4Gamesave save1;
    late NFL2K4Gamesave save2;
    setUpAll(() {
      save1 = NFL2K4Gamesave.fromPs2Save(File(_psuPath).readAsBytesSync());
      save2 = NFL2K4Gamesave.fromPs2Save(save1.toPs2PsuBytes());
    });

    test('isPs2Container = true after round-trip',
        () => expect(save2.isPs2Container, isTrue));

    test('isXbox = false after round-trip',
        () => expect(save2.isXbox, isFalse));

    test('all 32 teams have equal player counts', () {
      for (int t = 0; t < 32; t++) {
        expect(save2.getTeamPlayers(t).length,
            equals(save1.getTeamPlayers(t).length),
            reason: kTeamNames[t]);
      }
    });

    test('all 32 teams have identical Speed values', () {
      for (int t = 0; t < 32; t++) {
        final p1 = save1.getTeamPlayers(t);
        final p2 = save2.getTeamPlayers(t);
        for (int i = 0; i < p1.length; i++) {
          expect(p2[i].getAttribute('Speed'), equals(p1[i].getAttribute('Speed')),
              reason: '${kTeamNames[t]} player $i');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // MAX round-trip
  // ---------------------------------------------------------------------------
  group('MAX round-trip — toPs2MaxBytes() → fromPs2Save()', () {
    late NFL2K4Gamesave save1;
    late NFL2K4Gamesave save2;
    setUpAll(() {
      save1 = NFL2K4Gamesave.fromPs2Save(File(_maxPath).readAsBytesSync());
      save2 = NFL2K4Gamesave.fromPs2Save(save1.toPs2MaxBytes());
    });

    test('isPs2Container = true after round-trip',
        () => expect(save2.isPs2Container, isTrue));

    test('all 32 teams have identical Speed values', () {
      for (int t = 0; t < 32; t++) {
        final p1 = save1.getTeamPlayers(t);
        final p2 = save2.getTeamPlayers(t);
        for (int i = 0; i < p1.length; i++) {
          expect(p2[i].getAttribute('Speed'), equals(p1[i].getAttribute('Speed')),
              reason: '${kTeamNames[t]} player $i');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PS2 card round-trip
  // ---------------------------------------------------------------------------
  group('PS2 card round-trip — toPs2CardBytes() → fromPs2Card()', () {
    late NFL2K4Gamesave save1;
    late NFL2K4Gamesave save2;
    setUpAll(() {
      save1 = NFL2K4Gamesave.fromPs2Card(File(_ps2Card).readAsBytesSync());
      save2 = NFL2K4Gamesave.fromPs2Card(save1.toPs2CardBytes());
    });

    test('isPs2Container = true after round-trip',
        () => expect(save2.isPs2Container, isTrue));

    test('all 32 teams have equal player counts', () {
      for (int t = 0; t < 32; t++) {
        expect(save2.getTeamPlayers(t).length,
            equals(save1.getTeamPlayers(t).length),
            reason: kTeamNames[t]);
      }
    });

    test('all 32 teams have identical Speed values', () {
      for (int t = 0; t < 32; t++) {
        final p1 = save1.getTeamPlayers(t);
        final p2 = save2.getTeamPlayers(t);
        for (int i = 0; i < p1.length; i++) {
          expect(p2[i].getAttribute('Speed'), equals(p1[i].getAttribute('Speed')),
              reason: '${kTeamNames[t]} player $i');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Error cases
  // ---------------------------------------------------------------------------
  group('Error cases', () {
    test('fromPs2Save() with zeroed bytes throws', () {
      expect(
        () => NFL2K4Gamesave.fromPs2Save(List.filled(1024, 0)),
        throwsA(anything),
      );
    });

    test('fromPs2Card() on empty formatted card throws FormatException', () {
      final emptyCard = Ps2Card.format().toBytes();
      expect(
        () => NFL2K4Gamesave.fromPs2Card(emptyCard),
        throwsA(isA<FormatException>()),
      );
    });

    test('toXboxMUBytes() on a PS2 save throws StateError', () {
      final save = NFL2K4Gamesave.fromPs2Save(File(_psuPath).readAsBytesSync());
      expect(() => save.toXboxMUBytes(), throwsStateError);
    });
  });
}
