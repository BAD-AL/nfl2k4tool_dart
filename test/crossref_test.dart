import 'dart:io';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'test_helpers.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Detect delimiter from the first (header) line — tab wins over comma.
String _detectDelimiter(String headerLine) =>
    headerLine.contains('\t') ? '\t' : ',';

/// Parse a delimited line respecting double-quoted fields (comma-mode only).
/// Tab-delimited files don't use quoting.
List<String> _parseLine(String line, String delim) {
  if (delim == '\t') {
    return line.split('\t').map((f) => f.trim()).toList();
  }
  // Comma: handle RFC-4180 quoting.
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
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      fields.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  fields.add(cur.toString().trim());
  return fields;
}

Map<String, int> _headerMap(List<String> headers) =>
    {for (int i = 0; i < headers.length; i++) headers[i].trim(): i};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  // NOTE: The test save files use fantasy all-star rosters (not real NFL team
  // assignments). Each fantasy team holds the best players at each position
  // regardless of their real-world team. This means:
  //   - Not every player in a TeamText CSV will be present in the save
  //     (backups and lower-rated players are omitted).
  //   - Players that ARE present may be on any fantasy team.
  // The tests below verify correctness of the data we DO read: for every
  // player found in the save by PBP, name / position / jersey must match.

  const testFilesDir = 'test/test_files';

  final saveFiles = {
    'roster':    'test/test_files/base_roster_2k4_savegame.dat',
    'franchise': 'test/test_files/base_franchise_2k4_savegame.dat',
  };

  // ── FA block tests ──────────────────────────────────────────────────────────
  group('FA block', () {
    test('roster has 191 free agents', () {
      final save = loadFile('test/test_files/base_roster_2k4_savegame.dat');
      expect(save.getFreeAgentPlayers().length, 191);
    });

    test('base franchise has 191 free agents', () {
      final save = loadFile(
          'test/test_files/base_franchise_2k4_savegame.dat');
      expect(save.getFreeAgentPlayers().length, 191);
    });

    test('franchise after 1 release has 192 free agents', () {
      final save = loadFile(
          'test/test_files/FranRel1FA.savegame.dat');
      expect(save.getFreeAgentPlayers().length, 192);
    });

    test('released player (Brandon Doman PBP=3556) appears in FA list', () {
      final save = loadFile(
          'test/test_files/FranRel1FA.savegame.dat');
      final fa = save.getFreeAgentPlayers();
      final doman = fa.where((p) => p.pbp == 3556).toList();
      expect(doman.length, 1);
      expect(doman.first.firstName, 'Brandon');
      expect(doman.first.lastName, 'Doman');
    });

    test('released player is no longer on any team', () {
      final save = loadFile(
          'test/test_files/FranRel1FA.savegame.dat');
      final teamPlayers = [
        for (int t = 0; t < kTeamSlots; t++) ...save.getTeamPlayers(t),
      ];
      expect(teamPlayers.any((p) => p.pbp == 3556), isFalse);
    });
  });

  for (final saveEntry in saveFiles.entries) {
    final saveLabel = saveEntry.key;
    final saveFilePath = saveEntry.value;

    group('[$saveLabel]', () {
      late Map<int, PlayerRecord> playersByPbp;

      setUpAll(() {
        final save = loadFile(saveFilePath);
        playersByPbp = {};
        for (int t = 0; t < kTeamSlots; t++) {
          for (final p in save.getTeamPlayers(t)) {
            playersByPbp[p.pbp] = p;
          }
        }
      });

      for (final csvFile
          in Directory(testFilesDir).listSync().whereType<File>()) {
        if (!csvFile.path.endsWith('.csv')) continue;

        final teamLabel =
            csvFile.uri.pathSegments.last.replaceAll('.csv', '');

        group('CrossRef $teamLabel', () {
          late List<Map<String, String>> csvRows;
          late int foundCount;

          setUpAll(() {
            final lines = csvFile.readAsLinesSync();
            final delim = _detectDelimiter(lines.first);
            final hMap = _headerMap(_parseLine(lines.first, delim));
            csvRows = [
              for (final line in lines.skip(1))
                if (line.trim().isNotEmpty)
                  {
                    for (final entry in hMap.entries)
                      if (entry.value < _parseLine(line, delim).length)
                        entry.key: _parseLine(line, delim)[entry.value],
                  }
            ];
            foundCount = csvRows
                .where((r) {
                  final pbp = int.tryParse(r['Play by Play'] ?? '');
                  return pbp != null && playersByPbp.containsKey(pbp);
                })
                .length;
          });

          test('at least one TeamText player found in save', () {
            expect(foundCount, greaterThan(0),
                reason: 'No $teamLabel players found in save by PBP');
          });

          test('first name matches for found players', () {
            final mismatches = <String>[];
            for (final row in csvRows) {
              final pbp = int.tryParse(row['Play by Play'] ?? '');
              if (pbp == null) continue;
              final player = playersByPbp[pbp];
              if (player == null) continue; // not in this save; skip
              final expected = row['First'] ?? '';
              final actual = player.firstName;
              if (actual != expected) {
                mismatches.add('PBP $pbp: expected "$expected", got "$actual"');
              }
            }
            expect(mismatches, isEmpty, reason: mismatches.join('\n'));
          });

          test('last name matches for found players', () {
            final mismatches = <String>[];
            for (final row in csvRows) {
              final pbp = int.tryParse(row['Play by Play'] ?? '');
              if (pbp == null) continue;
              final player = playersByPbp[pbp];
              if (player == null) continue;
              final expected = row['Last'] ?? '';
              final actual = player.lastName;
              if (actual != expected) {
                mismatches.add('PBP $pbp: expected "$expected", got "$actual"');
              }
            }
            expect(mismatches, isEmpty, reason: mismatches.join('\n'));
          });

          test('position matches for found players', () {
            final mismatches = <String>[];
            for (final row in csvRows) {
              final pbp = int.tryParse(row['Play by Play'] ?? '');
              if (pbp == null) continue;
              final player = playersByPbp[pbp];
              if (player == null) continue;
              final expected = row['Position'] ?? '';
              final actual = player.position;
              if (actual != expected) {
                mismatches.add(
                    'PBP $pbp (${row['First']} ${row['Last']}): '
                    'expected "$expected", got "$actual"');
              }
            }
            expect(mismatches, isEmpty, reason: mismatches.join('\n'));
          });

          test('jersey number matches for found players', () {
            final mismatches = <String>[];
            for (final row in csvRows) {
              final pbp = int.tryParse(row['Play by Play'] ?? '');
              if (pbp == null) continue;
              final player = playersByPbp[pbp];
              if (player == null) continue;
              final expected = int.tryParse(row['Jersey #'] ?? '');
              if (expected == null) continue;
              final actual = player.jerseyNumber;
              if (actual != expected) {
                mismatches.add(
                    'PBP $pbp (${row['First']} ${row['Last']}): '
                    'expected #$expected, got #$actual');
              }
            }
            expect(mismatches, isEmpty, reason: mismatches.join('\n'));
          });

          test('college matches for found players', () {
            final mismatches = <String>[];
            for (final row in csvRows) {
              final pbp = int.tryParse(row['Play by Play'] ?? '');
              if (pbp == null) continue;
              final player = playersByPbp[pbp];
              if (player == null) continue;
              final expected = row['College'] ?? '';
              if (expected.isEmpty) continue;
              final actual = player.college;
              if (actual != expected) {
                mismatches.add(
                    'PBP $pbp (${row['First']} ${row['Last']}): '
                    'expected "$expected", got "$actual"');
              }
            }
            expect(mismatches, isEmpty, reason: mismatches.join('\n'));
          });

          test('visor matches for found players', () {
            final mismatches = <String>[];
            for (final row in csvRows) {
              final pbp = int.tryParse(row['Play by Play'] ?? '');
              if (pbp == null) continue;
              final player = playersByPbp[pbp];
              if (player == null) continue;
              final expected = row['Face Shield'] ?? '';
              if (expected.isEmpty) continue;
              final actual = player.getAttribute('Visor');
              if (actual != expected) {
                mismatches.add(
                    'PBP $pbp (${row['First']} ${row['Last']}): '
                    'expected "$expected", got "$actual"');
              }
            }
            expect(mismatches, isEmpty, reason: mismatches.join('\n'));
          });
        });
      }
    });
  }
}
