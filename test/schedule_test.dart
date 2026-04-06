import 'dart:io';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'test_helpers.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _franchisePath = 'test/test_files/base_franchise_2k4_savegame.dat';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Schedule round-trip', () {
    test('extract → apply → binary identical', () {
      // Load the save and capture the raw schedule bytes before anything.
      final save1 = loadFile(_franchisePath);
      final scheduleBytes1 = List<int>.from(
        save1.bytes.sublist(
          save1.base + kScheduleGd,
          save1.base + kScheduleGd + kScheduleWeeks * (kScheduleGamesPerWeek + 1) * kScheduleGameStride,
        ),
      );

      // Extract schedule as structured data, then apply it back.
      final schedule = save1.getSchedule();
      save1.setSchedule(schedule);

      // Capture schedule bytes after round-trip.
      final scheduleBytes2 = List<int>.from(
        save1.bytes.sublist(
          save1.base + kScheduleGd,
          save1.base + kScheduleGd + kScheduleWeeks * (kScheduleGamesPerWeek + 1) * kScheduleGameStride,
        ),
      );

      expect(scheduleBytes2, equals(scheduleBytes1),
          reason: 'Schedule bytes should be identical after extract → apply');
    });
  });

  group('Schedule content', () {
    test('week 1 has 16 games', () {
      final save = loadFile(_franchisePath);
      final weeks = save.getSchedule();
      final week1 = weeks[0].whereType<ScheduleGame>().toList();
      expect(week1.length, equals(16));
    });

    test('week 1 game 1 is Jets at Redskins', () {
      final save = loadFile(_franchisePath);
      final game = save.getSchedule()[0][0]!;
      expect(game.awayName.toLowerCase(), equals('jets'));
      expect(game.homeName.toLowerCase(), equals('redskins'));
    });

    test('all 17 weeks are present and non-empty', () {
      final save = loadFile(_franchisePath);
      final weeks = save.getSchedule();
      expect(weeks.length, equals(kScheduleWeeks));
      for (int w = 0; w < kScheduleWeeks; w++) {
        final games = weeks[w].whereType<ScheduleGame>().toList();
        expect(games, isNotEmpty, reason: 'Week ${w + 1} should have at least one game');
      }
    });

    test('roster save throws StateError on getSchedule', () {
      final save = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      expect(() => save.getSchedule(), throwsStateError);
    });
  });

  group('schedule_2.txt', () {
    test('apply → re-extract matches the input file game-for-game', () {
      final text = File('test/test_files/schedule_2.txt').readAsStringSync();
      final save = loadFile(_franchisePath);

      // Parse the text so we know what to expect after apply.
      final existing = save.getSchedule();
      final parsed = parseScheduleText(text, existing);
      expect(parsed.errors, isEmpty,
          reason: 'schedule_2.txt should parse without errors:\n'
              '${parsed.errors.join('\n')}');

      // Apply to the save, then read back.
      save.setSchedule(parsed.weeks);
      final readBack = save.getSchedule();

      // Compare every week and game slot.
      for (int w = 0; w < kScheduleWeeks; w++) {
        final expected = parsed.weeks[w];
        final actual   = readBack[w];
        for (int g = 0; g < kScheduleGamesPerWeek; g++) {
          final exp = expected[g];
          final act = actual[g];
          if (exp == null) {
            expect(act, isNull,
                reason: 'Week ${w+1} slot ${g+1}: expected null game');
          } else {
            expect(act, isNotNull,
                reason: 'Week ${w+1} slot ${g+1}: expected game, got null');
            expect(act!.homeTeam, equals(exp.homeTeam),
                reason: 'Week ${w+1} slot ${g+1}: home team mismatch '
                    '(${act.homeName} vs ${exp.homeName})');
            expect(act.awayTeam, equals(exp.awayTeam),
                reason: 'Week ${w+1} slot ${g+1}: away team mismatch '
                    '(${act.awayName} vs ${exp.awayName})');
          }
        }
      }
    });
  });

  group('Schedule file round-trip', () {
    test('extract → text → apply → saveToFile → file binary identical to original', () {
      const outPath = 'test/test_files/test_franchise_schedule.dat';
      final save = loadFile(_franchisePath);

      // Extract schedule as text, parse it back, apply, and save to a new file.
      final weeks = save.getSchedule();
      final text  = scheduleToText(weeks);
      final result = parseScheduleText(text, weeks);
      expect(result.errors, isEmpty);
      save.setSchedule(result.weeks);
      saveFile(save, outPath);

      // Binary-compare every byte of the saved file against the original.
      final original = File(_franchisePath).readAsBytesSync();
      final saved    = File(outPath).readAsBytesSync();
      expect(saved.length, equals(original.length),
          reason: 'File sizes differ');
      for (int i = 0; i < original.length; i++) {
        if (saved[i] != original[i]) {
          fail('Files differ at byte 0x${i.toRadixString(16).toUpperCase()}: '
              'original=0x${original[i].toRadixString(16).padLeft(2, '0')} '
              'saved=0x${saved[i].toRadixString(16).padLeft(2, '0')}');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // schedule_2020.txt — two-phase distribution tests
  // ---------------------------------------------------------------------------

  group('schedule_2020.txt two-phase distribution', () {
    late List<List<ScheduleGame?>> parsed2020;

    setUp(() {
      final text = File('test/test_files/schedule_2020.txt').readAsStringSync();
      // Pass an empty existing (all nulls) so defaultGame uses hardcoded fallbacks.
      final emptyExisting = List<List<ScheduleGame?>>.generate(
          kScheduleWeeks, (_) => List<ScheduleGame?>.filled(kScheduleGamesPerWeek, null));
      final result = parseScheduleText(text, emptyExisting);
      // 256 games == 256 capacity: no drop/underfill warnings expected.
      expect(result.errors, isEmpty,
          reason: 'schedule_2020.txt should parse without errors:\n'
              '${result.errors.join('\n')}');
      parsed2020 = result.weeks;
    });

    test('each week has exactly kGamesPerWeek[w] non-null games', () {
      for (int w = 0; w < kScheduleWeeks; w++) {
        final count = parsed2020[w].whereType<ScheduleGame>().length;
        expect(count, equals(kGamesPerWeek[w]),
            reason: 'Week ${w + 1}: expected ${kGamesPerWeek[w]} games, got $count');
      }
    });

    test('week 1 slot 0 is chiefs at texans (first game in file, no redistribution)', () {
      final g = parsed2020[0][0];
      expect(g, isNotNull);
      expect(g!.awayName, equals('chiefs'));
      expect(g.homeName, equals('texans'));
    });

    test('week 3 slot 0 is dolphins at jaguars (game 33 flat, redistribution from 16→14)', () {
      // File week 1 has 16 games + file week 2 has 16 games = 32 games consumed by
      // output weeks 1-2.  Output week 3 starts at game 33 = first game of file week 3.
      final g = parsed2020[2][0];
      expect(g, isNotNull);
      expect(g!.awayName, equals('dolphins'));
      expect(g.homeName, equals('jaguars'));
    });

    test('week 4 slot 0 is packers at saints (game 47, overflow from file week 3)', () {
      // Output week 3 takes 14 of file week 3's 16 games (games 33-46).
      // Games 47-48 of the flat list are file week 3 slots 15-16:
      //   slot 15 = "packers at saints", slot 16 = "chiefs at ravens".
      // These become output week 4 slots 0-1.
      final g = parsed2020[3][0];
      expect(g, isNotNull);
      expect(g!.awayName, equals('packers'));
      expect(g.homeName, equals('saints'));
    });

    test('week 4 slot 1 is chiefs at ravens (game 48, second overflow from file week 3)', () {
      final g = parsed2020[3][1];
      expect(g, isNotNull);
      expect(g!.awayName, equals('chiefs'));
      expect(g.homeName, equals('ravens'));
    });

    test('total non-null games across all 17 weeks equals 256', () {
      final total = parsed2020.fold<int>(
          0, (sum, wk) => sum + wk.whereType<ScheduleGame>().length);
      expect(total, equals(256));
    });
  });

  // ---------------------------------------------------------------------------
  // Overflow / capacity tests
  // ---------------------------------------------------------------------------

  group('parseScheduleText overflow', () {
    test('games beyond total capacity are dropped with a warning', () {
      // Build a synthetic schedule with 258 games (2 over the 256 capacity).
      // We use only "jets at redskins" repeated because team names are always valid.
      final buf = StringBuffer();
      buf.writeln('Week 1');
      for (int i = 0; i < 258; i++) {
        buf.writeln('jets at redskins');
      }
      final emptyExisting = List<List<ScheduleGame?>>.generate(
          kScheduleWeeks, (_) => List<ScheduleGame?>.filled(kScheduleGamesPerWeek, null));
      final result = parseScheduleText(buf.toString(), emptyExisting);

      // Exactly 2 games should be dropped.
      expect(result.errors.any((e) => e.contains('2 game(s) exceeded')), isTrue,
          reason: 'Expected a warning about 2 dropped games, got: ${result.errors}');

      // Total scheduled games must not exceed capacity.
      final total = result.weeks.fold<int>(
          0, (sum, wk) => sum + wk.whereType<ScheduleGame>().length);
      expect(total, equals(256));
    });

    test('each week never exceeds its kGamesPerWeek cap even with overflow input', () {
      // 300 games all in "Week 1" header — everything spills through all 17 weeks.
      final buf = StringBuffer();
      buf.writeln('Week 1');
      for (int i = 0; i < 300; i++) {
        buf.writeln('bills at patriots');
      }
      final emptyExisting = List<List<ScheduleGame?>>.generate(
          kScheduleWeeks, (_) => List<ScheduleGame?>.filled(kScheduleGamesPerWeek, null));
      final result = parseScheduleText(buf.toString(), emptyExisting);

      for (int w = 0; w < kScheduleWeeks; w++) {
        final count = result.weeks[w].whereType<ScheduleGame>().length;
        expect(count, lessThanOrEqualTo(kGamesPerWeek[w]),
            reason: 'Week ${w + 1}: $count games exceeds cap ${kGamesPerWeek[w]}');
      }
    });

    test('underfill produces a warning listing the actual game count', () {
      // Only 5 games — well under the 256 capacity.
      const text = '''
Week 1
jets at redskins
chiefs at raiders
bears at lions
packers at vikings
steelers at ravens
''';
      final emptyExisting = List<List<ScheduleGame?>>.generate(
          kScheduleWeeks, (_) => List<ScheduleGame?>.filled(kScheduleGamesPerWeek, null));
      final result = parseScheduleText(text, emptyExisting);

      expect(result.errors.any((e) => e.contains('only 5 game(s) found')), isTrue,
          reason: 'Expected underfill warning, got: ${result.errors}');
    });
  });

  group('Schedule text round-trip', () {
    test('extract → scheduleToText → parseScheduleText → apply → binary identical', () {
      final save = loadFile(_franchisePath);

      // Capture original bytes.
      final before = List<int>.from(
        save.bytes.sublist(
          save.base + kScheduleGd,
          save.base + kScheduleGd + kScheduleWeeks * (kScheduleGamesPerWeek + 1) * kScheduleGameStride,
        ),
      );

      // Extract → text → parse → apply.
      final weeks = save.getSchedule();
      final text  = scheduleToText(weeks);
      final result = parseScheduleText(text, weeks);

      expect(result.errors, isEmpty,
          reason: 'Text round-trip should produce no errors:\n'
              '${result.errors.join('\n')}');

      save.setSchedule(result.weeks);

      final after = List<int>.from(
        save.bytes.sublist(
          save.base + kScheduleGd,
          save.base + kScheduleGd + kScheduleWeeks * (kScheduleGamesPerWeek + 1) * kScheduleGameStride,
        ),
      );

      expect(after, equals(before),
          reason: 'Schedule bytes should be identical after text round-trip');
    });
  });
}
