import 'dart:io';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'test_helpers.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Strips comment lines (starting with #) and blank lines, normalises line
/// endings.  Used to compare two exports while ignoring the header comment.
String _stripped(String text) => text
    .split(RegExp(r'\r?\n'))
    .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
    .join('\n');

/// Returns the Speed attribute (as int) for a player found by exact name.
int _speed(NFL2K4Gamesave save, String fname, String lname) {
  final matches = save
      .findPlayers('$fname $lname')
      .where((m) => m.player.firstName == fname && m.player.lastName == lname)
      .toList();
  expect(matches, isNotEmpty, reason: '$fname $lname not found in save');
  return int.parse(matches.first.player.getAttribute('speed'));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Round-trip test ────────────────────────────────────────────────────────
  group('InputParser round-trip', () {
    test('roster: extract → apply → re-extract is identical', () {
      final save1 = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      final text1 = save1.toText(RosterKey.all);

      // Apply text back to a freshly loaded copy of the same save.
      final save2 = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      final result = InputParser(save2).applyText(text1);

      expect(result.errors, isEmpty,
          reason: 'Round-trip should produce no errors:\n'
              '${result.errors.join('\n')}');
      expect(result.updated, greaterThan(0));

      String text2 = save2.toText(RosterKey.all);
      String s1 = _stripped(text1);
      String s2 = _stripped(text2);
      expect(s2, equals(s1));
    });

    test('franchise: extract → apply → re-extract is identical', () {
      const path = 'test/test_files/base_franchise_2k4_savegame.dat';
      final save1 = loadFile(path);
      final text1 = save1.toText(RosterKey.all);

      final save2 = loadFile(path);
      final result = InputParser(save2).applyText(text1);

      expect(result.errors, isEmpty,
          reason: 'Round-trip should produce no errors:\n'
              '${result.errors.join('\n')}');
      expect(result.updated, greaterThan(0));

      final text2 = save2.toText(RosterKey.all);
      expect(_stripped(text2), equals(_stripped(text1)));
    });
  });

  // ── LookupAndModify mode ──────────────────────────────────────────────────
  group('InputParser LookupAndModify', () {
    const rosterPath = 'test/test_files/base_roster_2k4_savegame.dat';
    final namespeedKey = RosterKey.parse('fname,lname,speed');

    // Test 1: basic — modify a single known player's attribute by name -------
    test('modifies a known player attribute by name', () {
      final save = loadFile(rosterPath);
      final originalSpeed = _speed(save, 'Jeff', 'Garcia');

      const text = 'LookupAndModify\n'
          '#fname,lname,speed\n'
          'Jeff,Garcia,55\n';
      final result = InputParser(save).applyText(text, key: namespeedKey);

      expect(result.errors, isEmpty);
      expect(result.updated, equals(1));
      expect(_speed(save, 'Jeff', 'Garcia'), equals(55));
      expect(55, isNot(equals(originalSpeed)),
          reason: 'Sanity: chosen value 55 must differ from original');
    });

    // Test 2: order independence — players from different teams --------------
    test('updates players from different teams in arbitrary order', () {
      final save = loadFile(rosterPath);

      // Jeff Garcia = 49ers QB; Olin Kreutz = Bears C; Ahmed Plummer = 49ers CB
      const text = 'LookupAndModify\n'
          '#fname,lname,speed\n'
          'Olin,Kreutz,11\n'
          'Jeff,Garcia,22\n'
          'Ahmed,Plummer,33\n';
      final result = InputParser(save).applyText(text, key: namespeedKey);

      expect(result.errors, isEmpty);
      expect(result.updated, equals(3));
      expect(_speed(save, 'Olin', 'Kreutz'), equals(11));
      expect(_speed(save, 'Jeff', 'Garcia'), equals(22));
      expect(_speed(save, 'Ahmed', 'Plummer'), equals(33));
    });

    // Test 3: player not found → error logged, not a crash ------------------
    test('logs error for unknown player and counts it as skipped', () {
      final save = loadFile(rosterPath);

      const text = 'LookupAndModify\n'
          '#fname,lname,speed\n'
          'Jeff,Garcia,77\n'
          'Brock,Purdy,99\n'; // 2024 player not in 2K4 roster
      final result = InputParser(save).applyText(text, key: namespeedKey);

      expect(result.updated, equals(1));
      expect(result.skipped, equals(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Brock'));
    });

    // Test 4: ? sentinel skips a field without touching the player -----------
    test('? sentinel leaves attribute unchanged while other fields are applied',
        () {
      final save = loadFile(rosterPath);
      final origSpeed = _speed(save, 'Jeff', 'Garcia');
      final agilityKey = RosterKey.parse('fname,lname,speed,agility');

      // speed is '?' — must remain at original.
      // agility is 11 — confirms the row IS applied.
      const text = 'LookupAndModify\n'
          '#fname,lname,speed,agility\n'
          'Jeff,Garcia,?,11\n';
      final result = InputParser(save).applyText(text, key: agilityKey);

      expect(result.errors, isEmpty);
      expect(result.updated, equals(1));
      expect(_speed(save, 'Jeff', 'Garcia'), equals(origSpeed),
          reason: 'speed should be unchanged because ? was used');

      final agility = int.parse(save
          .findPlayers('Jeff Garcia')
          .firstWhere((m) =>
              m.player.firstName == 'Jeff' && m.player.lastName == 'Garcia')
          .player
          .getAttribute('agility'));
      expect(agility, equals(11));
    });

    // Test 5: Team= line resets mode back to sequential ----------------------
    test('Team= after LookupAndModify switches back to sequential mode', () {
      final save = loadFile(rosterPath);

      // Resolve 49ers team index and grab the slot-0 player name.
      final ninerIdx =
          kTeamNames.indexWhere((n) => n.toLowerCase().contains('49ers'));
      expect(ninerIdx, isNot(equals(-1)), reason: '49ers must be in kTeamNames');
      final niners = save.getTeamPlayers(ninerIdx);
      final slot0 = niners[0];

      // LookupAndModify sets Garcia's speed to 44.
      // Team = 49ers switches back to sequential; '?,?,55' uses sentinels for
      // the fname/lname columns so only speed (column 2) is written → slot-0
      // of the 49ers gets speed=55.
      final text = 'LookupAndModify\n'
          '#fname,lname,speed\n'
          'Jeff,Garcia,44\n'
          'Team = 49ers\n'
          '?,?,55\n';
      final result = InputParser(save).applyText(text, key: namespeedKey);

      expect(result.errors, isEmpty,
          reason: 'Unexpected errors:\n${result.errors.join('\n')}');
      expect(_speed(save, 'Jeff', 'Garcia'), equals(44),
          reason: 'Garcia should have been set by LookupAndModify');
      expect(
          _speed(save, slot0.firstName, slot0.lastName),
          equals(55),
          reason:
              'Slot-0 (${slot0.firstName} ${slot0.lastName}) should have been '
              'set sequentially after Team= reset');
    });
  });

  // ── Week_6_2024 cross-game file ────────────────────────────────────────────
  group('InputParser Week_6_2024', () {
    test('applies without throwing and updates players', () {
      final text = File('test/test_files/Week_6_2024-ab-app.txt')
          .readAsStringSync();
      final save =
          loadFile('test/test_files/base_roster_2k4_savegame.dat');

      final result = InputParser(save).applyText(text);

      // Players should have been written to (even if the 2024 data doesn't
      // match 2K4 players semantically, the slots are still updated).
      expect(result.updated, greaterThan(0));

      // Structural errors (unknown teams, exceeded player limits) must be
      // absent.  Value-incompatibility errors (unknown college, out-of-range
      // enum from 2K5 data) are tolerated.
      final structural = result.errors
          .where((e) =>
              e.startsWith('Unknown team') ||
              e.contains('team player limit'))
          .toList();
      expect(structural, isEmpty,
          reason: 'Structural errors found:\n${structural.join('\n')}');
    });

    test('auto-detects key from # header line', () {
      // The file's first line is '#Position,fname,lname,...' — a comment.
      // The parser should read it to determine the column order.
      final text = File('test/test_files/Week_6_2024-ab-app.txt')
          .readAsStringSync();
      final save =
          loadFile('test/test_files/base_roster_2k4_savegame.dat');

      // Apply with NO explicit key — the # header must supply it.
      final result = InputParser(save).applyText(text);

      // If the key was NOT detected, most setAttribute calls would fail
      // because column 0 ('QB'/'RB' etc.) would be attributed to the wrong
      // field.  A healthy update count confirms the key was resolved.
      expect(result.updated, greaterThan(0));
    });
  });

  // ── Skin mapping ───────────────────────────────────────────────────────────
  group('mapSkin', () {
    test('maps all 22 2K5 skin values to Skin1–Skin6', () {
      // Each group of three (plus Skin6's extended set) must collapse correctly.
      expect(mapSkin('Skin1'),  equals('Skin1'));
      expect(mapSkin('Skin9'),  equals('Skin1'));
      expect(mapSkin('Skin17'), equals('Skin1'));

      expect(mapSkin('Skin2'),  equals('Skin2'));
      expect(mapSkin('Skin10'), equals('Skin2'));
      expect(mapSkin('Skin18'), equals('Skin2'));

      expect(mapSkin('Skin3'),  equals('Skin3'));
      expect(mapSkin('Skin11'), equals('Skin3'));
      expect(mapSkin('Skin19'), equals('Skin3'));

      expect(mapSkin('Skin4'),  equals('Skin4'));
      expect(mapSkin('Skin12'), equals('Skin4'));
      expect(mapSkin('Skin20'), equals('Skin4'));

      expect(mapSkin('Skin5'),  equals('Skin5'));
      expect(mapSkin('Skin13'), equals('Skin5'));
      expect(mapSkin('Skin21'), equals('Skin5'));

      expect(mapSkin('Skin6'),  equals('Skin6'));
      expect(mapSkin('Skin7'),  equals('Skin6'));
      expect(mapSkin('Skin8'),  equals('Skin6'));
      expect(mapSkin('Skin14'), equals('Skin6'));
      expect(mapSkin('Skin15'), equals('Skin6'));
      expect(mapSkin('Skin16'), equals('Skin6'));
      expect(mapSkin('Skin22'), equals('Skin6'));
    });

    test('unknown skin value falls back to Skin6', () {
      expect(mapSkin('Skin99'), equals('Skin6'));
      expect(mapSkin('Skin0'),  equals('Skin6'));
    });


    test('Week_6 apply stores only Skin1–Skin6 values in 2K4 save', () {

      // Week_6 is in slot order: 49ers slot 0=Purdy(Skin1), slot 1=Dobbs(Skin3),
      // slot 4=Mason(Skin6).  We verify by slot position since name writes may
      // fail for longer 2024 names that exceed the name-section slack.
      String text = File('test/test_files/Week_6_2024-ab-app.txt').readAsStringSync();
      NFL2K4Gamesave save = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      InputParser(save).applyText(text);

      int ninersIdx = kTeamNames.indexWhere((n) => n.toLowerCase().contains('49ers'));
      List<PlayerRecord> niners = save.getTeamPlayers(ninersIdx);

      // Purdy  → Skin1
      expect(niners[0].getAttribute('Position'), equals('QB'));
      expect(niners[0].getAttribute('lname'), equals('Purdy'));
      expect(niners[0].getAttribute('skin'), equals('Skin1'));
      // Dobbs  → Skin3
      expect(niners[1].getAttribute('Position'), equals('QB'));
      expect(niners[1].getAttribute('lname'), equals('Dobbs'));
      expect(niners[1].getAttribute('skin'), equals('Skin3'));
      // Mason  → Skin6
      expect(niners[4].getAttribute('Position'), equals('RB'));
      expect(niners[4].getAttribute('lname'), equals('Mason'));
      expect(niners[4].getAttribute('skin'), equals('Skin6'));
    });
  });

  // ── mapFace ───────────────────────────────────────────────────────────────
  group('mapFace', () {
    test('Face1–Face15 pass through unchanged', () {
      for (int i = 1; i <= 15; i++) {
        expect(mapFace('Face$i'), equals('Face$i'));
      }
    });

    test('maps 2K5 out-of-range raw values to 2K4 equivalents', () {
      expect(mapFace('16'), equals('Face1'));
      expect(mapFace('17'), equals('Face2'));
      expect(mapFace('18'), equals('Face3'));
      expect(mapFace('19'), equals('Face4'));
      expect(mapFace('20'), equals('Face5'));
      expect(mapFace('21'), equals('Face6'));
      expect(mapFace('22'), equals('Face15'));
    });

    test('raw 15 (valid 2K4 round-trip value) is unchanged', () {
      expect(mapFace('15'), equals('15'));
    });

    test('Week_6 apply stores only Face1–Face15 in 2K4 save', () {
      final text = File('test/test_files/Week_6_2024-ab-app.txt').readAsStringSync();
      final save = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      InputParser(save).applyText(text);

      // Verify no player has a face value outside Face1–Face15.
      final faceRe = RegExp(r'^Face(\d+)$');
      for (final team in save.allTeams) {
        for (final p in team.players) {
          final faceStr = p.getAttribute('face');
          final m = faceRe.firstMatch(faceStr);
          if (m != null) {
            expect(int.parse(m.group(1)!), lessThanOrEqualTo(15),
                reason: '${p.fullName} has out-of-range face: $faceStr');
          }
        }
      }
    });
  });

  // ── College normalization ─────────────────────────────────────────────────
  group('college normalization', () {
    late NFL2K4Gamesave save;
    late PlayerRecord player;

    setUp(() {
      save = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      player = save.getTeamPlayers(0).first;
    });

    test('2K4 college name sets directly', () {
      player.setAttribute('college', 'Miami (Fla.)');
      expect(player.getAttribute('college'), equals('Miami (Fla.)'));
    });

    test('2K5 college name is normalised to 2K4 equivalent', () {
      player.setAttribute('college', 'Miami, FL');
      expect(player.getAttribute('college'), equals('Miami (Fla.)'));
    });

    test('unknown college falls back to None', () {
      player.setAttribute('college', 'Sega U.');
      expect(player.getAttribute('college'), equals('None'));
    });

    test('all kCollegeNormalize values resolve to valid 2K4 colleges', () {
      for (final entry in kCollegeNormalize.entries) {
        expect(kCollegeINI.containsKey(entry.value), isTrue,
            reason: '${entry.key} → ${entry.value} not found in kCollegeINI');
      }
    });

    test('further 2K5 name normalisations', () {
      final cases = {
        'Albany State, GA':    'Albany State (GA)',
        'Augustana, SD':       'Augustana (SD)',
        'Indiana, PA':         'Indiana (PA)',
        'Miami, OH':           'Miami (Ohio)',
        'Middle Tennessee St': 'Middle Tennessee St.',
        'North Carolina St':   'North Carolina State',
        'South Carolina St':   'South Carolina State',
        'Southern Miss':       'Southern Mississippi',
        'WI-Stevens Pt.':      'Wisconsin-Stevens Pt.',
        'WI-Whitewater':       'Wisconsin-Whitewater',
        'Wayne State, NE':     'Wayne State, Neb.',
        'NW Missouri St':      'Northwest Missouri St.',
        'NW Oklahoma St':      'Northwest Oklahoma St.',
        'TX A&M-Kingsville':   'Texas A&M-Kingsville',
      };
      for (final entry in cases.entries) {
        player.setAttribute('college', entry.key);
        expect(player.getAttribute('college'), equals(entry.value),
            reason: '${entry.key} should normalise to ${entry.value}');
      }
    });

    test('other unknown colleges fall back to None', () {
      for (final name in ['Barnum & Bailey', 'JBDW Brown Studio', 'Idaho State',
                          'Nicholls State', 'Cortland State', 'Tusculum']) {
        player.setAttribute('college', name);
        expect(player.getAttribute('college'), equals('None'),
            reason: '$name should fall back to None');
      }
    });

    test('Week_6 apply produces no unknown-college errors', () {
      final text = File('test/test_files/Week_6_2024-ab-app.txt').readAsStringSync();
      final result = InputParser(save).applyText(text);
      final collegeErrors = result.errors
          .where((e) => e.toLowerCase().contains('college'))
          .toList();
      expect(collegeErrors, isEmpty,
          reason: 'Unexpected college errors:\n${collegeErrors.join('\n')}');
    });

    test('Week_6 apply stores only valid 2K4 college names', () {
      final text = File('test/test_files/Week_6_2024-ab-app.txt').readAsStringSync();
      InputParser(save).applyText(text);
      for (final team in save.allTeams) {
        for (final p in team.players) {
          final c = p.getAttribute('college');
          expect(kCollegeINI.containsKey(c), isTrue,
              reason: '${p.fullName} has invalid college: $c');
        }
      }
    });
  });

  // ── TeamData ──────────────────────────────────────────────────────────────
  group('TeamData', () {
    const rosterPath = 'test/test_files/base_roster_2k4_savegame.dat';

    test('getTeamField returns non-empty values for all 32 NFL teams', () {
      final save = loadFile(rosterPath);
      for (int t = 0; t < 32; t++) {
        final nick   = save.getTeamField(t, 'Nickname');
        final abbrev = save.getTeamField(t, 'Abbrev');
        final logo   = save.getTeamField(t, 'Logo');
        final jersey = save.getTeamField(t, 'DefaultJersey');
        expect(nick,   isNotEmpty, reason: 'team $t nickname empty');
        expect(abbrev, isNotEmpty, reason: 'team $t abbrev empty');
        expect(int.tryParse(logo),   isNotNull, reason: 'team $t logo not numeric');
        expect(int.tryParse(jersey), isNotNull, reason: 'team $t jersey not numeric');
      }
    });

    test('logo indices are unique across all 32 teams', () {
      final save = loadFile(rosterPath);
      final logos = <int>{};
      for (int t = 0; t < 32; t++) {
        final logo = int.parse(save.getTeamField(t, 'Logo'));
        expect(logos.add(logo), isTrue,
            reason: 'duplicate logo index $logo at team $t (${kTeamNames[t]})');
      }
    });

    test('getTeamField stadium and city are non-empty for all 32 teams', () {
      final save = loadFile(rosterPath);
      for (int t = 0; t < 32; t++) {
        final stadium = save.getTeamField(t, 'Stadium');
        final city    = save.getTeamField(t, 'City');
        expect(stadium, isNotEmpty, reason: 'team $t (${kTeamNames[t]}) stadium empty');
        expect(city,    isNotEmpty, reason: 'team $t (${kTeamNames[t]}) city empty');
      }
    });

    test('setTeamField Nickname round-trip', () {
      final save = loadFile(rosterPath);
      // 49ers nickname — write a shorter string then restore.
      final orig = save.getTeamField(0, 'Nickname');
      save.setTeamField(0, 'Nickname', 'SF');
      expect(save.getTeamField(0, 'Nickname'), equals('SF'));
      save.setTeamField(0, 'Nickname', orig);
      expect(save.getTeamField(0, 'Nickname'), equals(orig));
    });

    test('setTeamField Abbrev round-trip', () {
      final save = loadFile(rosterPath);
      final orig = save.getTeamField(0, 'Abbrev');
      save.setTeamField(0, 'Abbrev', 'X');
      expect(save.getTeamField(0, 'Abbrev'), equals('X'));
      save.setTeamField(0, 'Abbrev', orig);
      expect(save.getTeamField(0, 'Abbrev'), equals(orig));
    });

    test('setTeamField Nickname write does not corrupt adjacent team', () {
      final save = loadFile(rosterPath);
      final bearsNick = save.getTeamField(1, 'Nickname');
      save.setTeamField(0, 'Nickname', 'SF'); // shorter than '49ers'
      expect(save.getTeamField(1, 'Nickname'), equals(bearsNick),
          reason: 'Bears nickname should be unaffected');
    });

    test('setTeamField throws when string exceeds original length', () {
      final save = loadFile(rosterPath);
      final orig = save.getTeamField(0, 'Nickname');
      // Write a string longer than the original.
      expect(
          () => save.setTeamField(0, 'Nickname', orig + 'XXXXXXXXXXX'),
          throwsArgumentError);
    });

    test('toTeamDataText round-trip via InputParser', () {
      final save1 = loadFile(rosterPath);
      final text  = save1.toTeamDataText();

      // Parse the exported text back into a fresh copy.
      final save2 = loadFile(rosterPath);
      final result = InputParser(save2).applyText(text);

      expect(result.errors, isEmpty,
          reason: 'Round-trip should produce no errors:\n${result.errors.join('\n')}');
      expect(result.updated, equals(32));

      // All 32 teams should have identical field values after round-trip.
      // Stadium and Logo are excluded from the export and not settable.
      for (int t = 0; t < 32; t++) {
        for (final field in ['Nickname', 'Abbrev', 'City', 'AbbrAlt', 'Playbook']) {
          expect(save2.getTeamField(t, field), equals(save1.getTeamField(t, field)),
              reason: 'team ${kTeamNames[t]} field $field differs after round-trip');
        }
      }
    });

    test('InputParser TeamDataKey= switches to team data mode', () {
      final save = loadFile(rosterPath);
      // 49ers nickname is '49ers' (5 chars); use same-length replacement.
      const text = 'TeamDataKey=Team,Nickname\n'
          '49ers,Niner\n';
      final result = InputParser(save).applyText(text);
      expect(result.errors, isEmpty,
          reason: 'Unexpected errors:\n${result.errors.join('\n')}');
      expect(result.updated, equals(1));
      expect(save.getTeamField(0, 'Nickname'), equals('Niner'));
    });

    test('InputParser ? sentinel skips TeamData field', () {
      final save  = loadFile(rosterPath);
      final origNick = save.getTeamField(0, 'Nickname');
      final origLogo = save.getTeamField(0, 'Logo');
      const text = 'TeamDataKey=Team,Nickname,DefaultJersey\n'
          '49ers,?,1\n';
      InputParser(save).applyText(text);
      expect(save.getTeamField(0, 'Nickname'), equals(origNick),
          reason: '? should leave nickname unchanged');
      //expect(save.getTeamField(0, 'DefaultJersey'), equals('1')); // TODO Fix DefaultJersey someday
      // Logo is not settable; verify it was not touched.
      expect(save.getTeamField(0, 'Logo'), equals(origLogo));
    });

    test('InputParser unknown team logs error and skips', () {
      final save = loadFile(rosterPath);
      const text = 'TeamDataKey=Team,Nickname\n'
          'Penguins,Pittsburgh\n';
      final result = InputParser(save).applyText(text);
      expect(result.skipped, equals(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Penguins'));
    });

    // TODO: Stadium and Logo setting not yet supported in-game.
    // test('setTeamField throws when Stadium name is unknown', () {
    //   final save = loadFile(rosterPath);
    //   expect(
    //       () => save.setTeamField(0, 'Stadium', '[No Such Stadium]'),
    //       throwsArgumentError);
    // });

    test('setTeamField throws when City exceeds original length', () {
      final save = loadFile(rosterPath);
      final orig = save.getTeamField(0, 'City');
      expect(
          () => save.setTeamField(0, 'City', orig + 'XXXXXXXXXXX'),
          throwsArgumentError);
    });

    // ── Playbook ──────────────────────────────────────────────────────────────
    group('Playbook', () {
      test('getTeamPlaybook returns a valid PB_ token for all 32 teams', () {
        final save = loadFile(rosterPath);
        for (int t = 0; t < 32; t++) {
          final pb = save.getTeamPlaybook(t);
          expect(kPlaybookNames.contains(pb), isTrue,
              reason: 'team $t (${kTeamNames[t]}) returned unknown token "$pb"');
        }
      });

      test('each team starts on its own PB_ token', () {
        final save = loadFile(rosterPath);
        for (int t = 0; t < 32; t++) {
          final expected = kPlaybookNames[t]; // table is in kTeamNames order
          final actual   = save.getTeamPlaybook(t);
          expect(actual, equals(expected),
              reason: 'team $t (${kTeamNames[t]}) expected $expected got $actual');
        }
      });

      test('setTeamPlaybook round-trip', () {
        final save = loadFile(rosterPath);
        final orig = save.getTeamPlaybook(0); // 49ers
        save.setTeamPlaybook(0, 'PB_West_Coast');
        expect(save.getTeamPlaybook(0), equals('PB_West_Coast'));
        save.setTeamPlaybook(0, orig);
        expect(save.getTeamPlaybook(0), equals(orig));
      });

      test('setTeamPlaybook throws on unknown token', () {
        final save = loadFile(rosterPath);
        expect(() => save.setTeamPlaybook(0, 'PB_NotReal'), throwsArgumentError);
      });

      test('getTeamField Playbook matches getTeamPlaybook', () {
        final save = loadFile(rosterPath);
        for (int t = 0; t < 32; t++) {
          expect(save.getTeamField(t, 'Playbook'), equals(save.getTeamPlaybook(t)));
        }
      });

      test('toTeamDataText round-trip preserves Playbook for all 32 teams', () {
        final save1 = loadFile(rosterPath);
        final text  = save1.toTeamDataText();

        final save2 = loadFile(rosterPath);
        InputParser(save2).applyText(text);

        for (int t = 0; t < 32; t++) {
          expect(save2.getTeamPlaybook(t), equals(save1.getTeamPlaybook(t)),
              reason: 'team ${kTeamNames[t]} playbook differs after round-trip');
        }
      });

      test('InputParser sets 49ers playbook to Bears playbook via TeamData', () {
        final save = loadFile(rosterPath);
        const text = 'TeamDataKey=TeamData,Team,Playbook\n'
            'TeamData,49ers,PB_Bears\n';
        final result = InputParser(save).applyText(text);
        expect(result.errors, isEmpty,
            reason: 'Unexpected errors:\n${result.errors.join('\n')}');
        expect(result.updated, equals(1));
        expect(save.getTeamPlaybook(0), equals('PB_Bears'),
            reason: '49ers playbook should now be PB_Bears');
      });

      test('franchise: getTeamPlaybook returns valid PB_ tokens', () {
        final save = loadFile('test/test_files/base_franchise_2k4_savegame.dat');
        for (int t = 0; t < 32; t++) {
          final pb = save.getTeamPlaybook(t);
          expect(kPlaybookNames.contains(pb), isTrue,
              reason: 'franchise team $t returned unknown token "$pb"');
        }
      });
    });

    // ── Franchise file ────────────────────────────────────────────────────────
    group('franchise', () {
      const franPath = 'test/test_files/base_franchise_2k4_savegame.dat';

      test('getTeamField returns non-empty values for all 32 NFL teams', () {
        final save = loadFile(franPath);
        for (int t = 0; t < 32; t++) {
          final nick    = save.getTeamField(t, 'Nickname');
          final abbrev  = save.getTeamField(t, 'Abbrev');
          final stadium = save.getTeamField(t, 'Stadium');
          final city    = save.getTeamField(t, 'City');
          expect(nick,    isNotEmpty, reason: 'team $t nickname empty');
          expect(abbrev,  isNotEmpty, reason: 'team $t abbrev empty');
          expect(stadium, isNotEmpty, reason: 'team $t stadium empty');
          expect(city,    isNotEmpty, reason: 'team $t city empty');
        }
      });

      // ── PlayerControlled ────────────────────────────────────────────────────
      group('PlayerControlled', () {
        const allPath = 'test/test_files/DefFran2K4_savegame.dat';
        const ninePath = 'test/test_files/DefFran49_savegame.dat';

        test('isTeamPlayerControlled: all-teams file has every team true', () {
          final save = loadFile(allPath);
          for (int t = 0; t < 32; t++) {
            expect(save.isTeamPlayerControlled(t), isTrue,
                reason: 'team ${kTeamNames[t]} should be player-controlled in all-teams file');
          }
        });

        test('isTeamPlayerControlled: 49ers-only file has exactly 49ers true', () {
          final save = loadFile(ninePath);
          for (int t = 0; t < 32; t++) {
            final expected = (t == 0); // only 49ers
            expect(save.isTeamPlayerControlled(t), equals(expected),
                reason: 'team ${kTeamNames[t]} player-controlled mismatch');
          }
        });

        test('setTeamPlayerControlled round-trip', () {
          final save = loadFile(franPath);
          final orig = save.isTeamPlayerControlled(0);
          save.setTeamPlayerControlled(0, !orig);
          expect(save.isTeamPlayerControlled(0), equals(!orig));
          save.setTeamPlayerControlled(0, orig); // restore
          expect(save.isTeamPlayerControlled(0), equals(orig));
        });

        test('setTeamField PlayerControlled round-trip via InputParser', () {
          final save = loadFile(franPath);
          final orig0 = save.isTeamPlayerControlled(0);
          final text = 'TeamDataKey=TeamData,Team,PlayerControlled\n'
              'TeamData,49ers,${orig0 ? 0 : 1}\n';
          final result = InputParser(save).applyText(text);
          expect(result.errors, isEmpty,
              reason: 'Unexpected errors:\n${result.errors.join('\n')}');
          expect(save.isTeamPlayerControlled(0), equals(!orig0));
        });

        test('toTeamDataText includes PlayerControlled column for franchise', () {
          final save = loadFile(allPath);
          final text = save.toTeamDataText();
          expect(text, contains('PlayerControlled'));
          // Every team should show 1 in the all-teams file.
          for (final line in text.split('\n').where((l) => l.startsWith('TeamData,'))) {
            expect(line, endsWith(',1'),
                reason: 'Expected PlayerControlled=1 in: $line');
          }
        });

        test('toTeamDataText PlayerControlled round-trip via InputParser', () {
          final save1 = loadFile(allPath);
          final text  = save1.toTeamDataText();
          final save2 = loadFile(allPath);
          final result = InputParser(save2).applyText(text);
          expect(result.errors, isEmpty,
              reason: 'Round-trip errors:\n${result.errors.join('\n')}');
          for (int t = 0; t < 32; t++) {
            expect(save2.isTeamPlayerControlled(t), equals(save1.isTeamPlayerControlled(t)),
                reason: 'team ${kTeamNames[t]} PlayerControlled differs after round-trip');
          }
        });

        test('isTeamPlayerControlled throws on roster save', () {
          final save = loadFile(
              'test/test_files/base_roster_2k4_savegame.dat');
          expect(() => save.isTeamPlayerControlled(0), throwsStateError);
        });

        test('setTeamPlayerControlled throws on roster save', () {
          final save = loadFile(
              'test/test_files/base_roster_2k4_savegame.dat');
          expect(() => save.setTeamPlayerControlled(0, true), throwsStateError);
        });

        test('getPlayerControlledTeams returns correct list', () {
          final save = loadFile(ninePath);
          final teams = save.getPlayerControlledTeams();
          expect(teams, equals(['49ers']));
        });

        test('getPlayerControlledTeams throws on roster save', () {
          final save = loadFile(
              'test/test_files/base_roster_2k4_savegame.dat');
          expect(() => save.getPlayerControlledTeams(), throwsStateError);
        });

        test('InputParser PlayerControlled=[49ers,Bears] line sets both teams', () {
          final save = loadFile(allPath);
          // All teams start as player-controlled; after applying, only 49ers and Bears should be.
          final text = 'PlayerControlled=[49ers,Bears]\n';
          final result = InputParser(save).applyText(text);
          expect(result.errors, isEmpty,
              reason: 'Unexpected errors:\n${result.errors.join('\n')}');
          expect(save.isTeamPlayerControlled(0), isTrue,  reason: '49ers should be PC');
          // Bears index: kTeamNames is alphabetical, Bears = index 1
          expect(save.isTeamPlayerControlled(1), isTrue,  reason: 'Bears should be PC');
          // All others should be false.
          for (int t = 0; t < 32; t++) {
            if (t == 0 || t == 1) continue;
            expect(save.isTeamPlayerControlled(t), isFalse,
                reason: 'team ${kTeamNames[t]} should not be PC');
          }
        });

        test('InputParser PlayerControlled=All sets all teams', () {
          final save = loadFile(ninePath);
          // Only 49ers start as PC; after All, all 32 should be.
          final text = 'PlayerControlled=All\n';
          final result = InputParser(save).applyText(text);
          expect(result.errors, isEmpty);
          for (int t = 0; t < 32; t++) {
            expect(save.isTeamPlayerControlled(t), isTrue,
                reason: 'team ${kTeamNames[t]} should be PC after All');
          }
        });
      });
    });
  });

  // ── CoachData ─────────────────────────────────────────────────────────────
  group('CoachData', () {
    const rosterPath = 'test/test_files/base_roster_2k4_savegame.dat';

    // Known base-roster values confirmed from -coach export.
    const int k49ersIdx  = 0;   // 49ers  — Dennis Erickson
    const int kEaglesIdx = 13;  // Eagles — Andy Reid

    const String kEaglesBody  = '[Andy Reid]';
    const String k49ersBody   = '[Dennis Erickson]';
    const int    kEaglesPhoto = 8021;
    const int    k49ersPhoto  = 8025;

    test('getCoachAttribute Body returns bracketed name', () {
      final save = loadFile(rosterPath);
      expect(save.getCoachAttribute(k49ersIdx,  'Body'), equals(k49ersBody));
      expect(save.getCoachAttribute(kEaglesIdx, 'Body'), equals(kEaglesBody));
    });

    test('getCoachAttribute Photo matches known base-roster values', () {
      final save = loadFile(rosterPath);
      expect(int.parse(save.getCoachAttribute(k49ersIdx,  'Photo')), equals(k49ersPhoto));
      expect(int.parse(save.getCoachAttribute(kEaglesIdx, 'Photo')), equals(kEaglesPhoto));
    });

    test('setCoachAttribute Body round-trip using bracketed name', () {
      final save = loadFile(rosterPath);

      // Copy Eagles coach Body onto the 49ers coach using bracketed name.
      save.setCoachAttribute(k49ersIdx, 'Body', kEaglesBody);
      expect(save.getCoachAttribute(k49ersIdx, 'Body'), equals(kEaglesBody));

      // Eagles coach must be unchanged.
      expect(save.getCoachAttribute(kEaglesIdx, 'Body'), equals(kEaglesBody));
    });

    test('setCoachAttribute Body accepts raw numeric for backward compat', () {
      final save = loadFile(rosterPath);
      save.setCoachAttribute(k49ersIdx, 'Body', '21'); // raw index for Andy Reid
      expect(save.getCoachAttribute(k49ersIdx, 'Body'), equals(kEaglesBody));
    });

    test('setCoachAttribute Body throws on unknown bracketed name', () {
      final save = loadFile(rosterPath);
      expect(
        () => save.setCoachAttribute(k49ersIdx, 'Body', '[Lovie Smith]'),
        throwsArgumentError,
      );
    });

    test('setCoachAttribute Body/Photo for 49ers does not corrupt adjacent coaches', () {
      final save = loadFile(rosterPath);

      // Record all other coaches' Body/Photo before the write.
      final before = <int, (String body, int photo)>{};
      for (int t = 0; t < 32; t++) {
        if (t == k49ersIdx) continue;
        before[t] = (
          save.getCoachAttribute(t, 'Body'),
          int.parse(save.getCoachAttribute(t, 'Photo')),
        );
      }

      save.setCoachAttribute(k49ersIdx, 'Body',  kEaglesBody);
      save.setCoachAttribute(k49ersIdx, 'Photo', kEaglesPhoto.toString());

      for (int t = 0; t < 32; t++) {
        if (t == k49ersIdx) continue;
        final (bodyBefore, photoBefore) = before[t]!;
        expect(save.getCoachAttribute(t, 'Body'),              equals(bodyBefore),
            reason: '${kTeamNames[t]} Body changed unexpectedly');
        expect(int.parse(save.getCoachAttribute(t, 'Photo')), equals(photoBefore),
            reason: '${kTeamNames[t]} Photo changed unexpectedly');
      }
    });

    test('toCoachDataText round-trip via InputParser preserves Body and Photo for all 32 coaches', () {
      final save1 = loadFile(rosterPath);
      final text  = save1.toCoachDataText();

      final save2 = loadFile(rosterPath);
      final result = InputParser(save2).applyText(text);

      expect(result.errors, isEmpty,
          reason: 'Round-trip should produce no errors:\n${result.errors.join('\n')}');
      expect(result.updated, equals(32));

      for (int t = 0; t < 32; t++) {
        expect(save2.getCoachAttribute(t, 'Body'),  equals(save1.getCoachAttribute(t, 'Body')),
            reason: '${kTeamNames[t]} Body differs after round-trip');
        expect(save2.getCoachAttribute(t, 'Photo'), equals(save1.getCoachAttribute(t, 'Photo')),
            reason: '${kTeamNames[t]} Photo differs after round-trip');
      }
    });

    test('InputParser CoachKey= sets 49ers Body and Photo to Eagles values', () {
      final save = loadFile(rosterPath);
      final text = 'CoachKEY=Coach,Team,Body,Photo\n'
          'Coach,49ers,$kEaglesBody,$kEaglesPhoto\n';
      final result = InputParser(save).applyText(text);
      expect(result.errors, isEmpty,
          reason: 'Unexpected errors:\n${result.errors.join('\n')}');
      expect(result.updated, equals(1));
      expect(save.getCoachAttribute(k49ersIdx, 'Body'),              equals(kEaglesBody));
      expect(int.parse(save.getCoachAttribute(k49ersIdx, 'Photo')), equals(kEaglesPhoto));
    });

    test('InputParser CoachKey= logs error for unknown bracketed body name', () {
      final save = loadFile(rosterPath);
      const text = 'CoachKEY=Coach,Team,Body\n'
          'Coach,49ers,[Lovie Smith]\n';
      final result = InputParser(save).applyText(text);
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Lovie Smith'));
      // Body must be unchanged.
      expect(save.getCoachAttribute(k49ersIdx, 'Body'), equals(k49ersBody));
    });
  });

  // ── autoFixSkinFromPhoto ───────────────────────────────────────────────────
  group('autoFixSkinFromPhoto', () {
    test('Maxx Crosby skin is corrected to Skin1 from base-roster photo map', () {
      final save = loadFile('test/test_files/NFL24Fran.zip');

      final match = save
          .findPlayers('Maxx Crosby')
          .where((m) => m.player.firstName == 'Maxx' &&
                        m.player.lastName == 'Crosby')
          .first;
      final player = match.player;

      final initialSkin = player.getAttribute('skin');
      save.autoFixSkinFromPhoto();
      final fixedSkin = player.getAttribute('skin');

      expect(fixedSkin, isNot(equals(initialSkin)),
          reason: 'skin should have changed from $initialSkin');
      expect(fixedSkin, equals('Skin1'));
    });
  });
}
