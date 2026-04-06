import 'dart:io';
import 'package:test/test.dart';

import '../bin/nfl2k4tool_dart.dart';

const _rosterFile    = 'test/test_files/base_roster_2k4_savegame.dat';
const _franchiseFile = 'test/test_files/base_franchise_2k4_savegame.dat';
const _bin = 'bin/nfl2k4tool_dart.dart';

Future<ProcessResult> _run(List<String> args) =>
    Process.run('dart', ['run', _bin, ...args]);

/// RFC-4180-aware CSV split — handles quoted fields like `"Chicago, IL"`.
/// Returns unquoted field values.
List<String> _splitTdRow(String line) {
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
    } else {
      if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        fields.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
  }
  fields.add(cur.toString());
  return fields;
}

/// Re-quotes a value for CSV output if it contains a comma.
String _tdQuote(String s) => s.contains(',') ? '"$s"' : s;

void main() {
  group('CLI -td round-trip', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('nfl2k4_td_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('copy Bears TeamData to 49ers and verify round-trip via CLI', () async {
      // ── Step 1: export full team data ──────────────────────────────────────
      final exportResult = await _run([_rosterFile, '-td']);
      expect(exportResult.exitCode, 0,
          reason: 'export failed:\n${exportResult.stderr}');
      final lines = (exportResult.stdout as String).trim().split('\n');

      // For debugging, you can call the 'runMain' function and parse the output.
      //String output = runMain([_rosterFile, '-td']);
      //List<String> lines = output.trim().split('\n');
      
      // Current header (Stadium and Logo excluded — not settable in-game):
      //   TeamDataKey=TeamData,Team,Nickname,Abbrev,City,AbbrAlt,Playbook,DefaultJersey
      // Indices:                0    1        2      3     4       5        6        7
      expect(lines.first,
          startsWith('TeamDataKey=TeamData,Team,'),
          reason: 'unexpected TeamData header');

      const int iNick    = 2;
      // iAbbrev = 3  — skipped (capacity: 49ers "SF" slot < "CHI")
      const int iCity    = 4;
      // iAbbrAlt = 5 — skipped (same capacity constraint)
      const int iBook    = 6;
      //const int iJersey  = 7; //TODO: figure out DefaultJersey 

      final ninerLine = lines.firstWhere(
          (l) => l.startsWith('TeamData,49ers,'),
          orElse: () => throw StateError('No 49ers row in export'));
      final bearLine = lines.firstWhere(
          (l) => l.startsWith('TeamData,Bears,'),
          orElse: () => throw StateError('No Bears row in export'));

      final bearParts  = _splitTdRow(bearLine);
      final ninerParts = _splitTdRow(ninerLine);

      // Sanity-check: they start on different playbooks.
      expect(bearParts[iBook],  equals('PB_Bears'));
      expect(ninerParts[iBook], equals('PB_49ers'));

      // ── Step 2: build apply text ────────────────────────────────────────────
      // Skip Abbrev and AbbrAlt (3-char "CHI" won't fit the 2-char "SF" slot).
      // Stadium and Logo are not settable (see toTeamDataText comment).
      const applyHeader =
          'TeamDataKey=TeamData,Team,Nickname,City,Playbook,DefaultJersey';

      final applyRow = [
        'TeamData',
        '49ers',
        bearParts[iNick],           // Nickname
        _tdQuote(bearParts[iCity]), // City (re-quoted if "City, ST" form)
        bearParts[iBook],           // Playbook
        //bearParts[iJersey],         // DefaultJersey
      ].join(',');

      final applyText = '$applyHeader\n$applyRow\n';

      final applyFile = File('${tmpDir.path}/bears_to_49ers.txt')
        ..writeAsStringSync(applyText);
      final outSave = '${tmpDir.path}/out.dat';

      // ── Step 3: apply via CLI ───────────────────────────────────────────────
      final applyResult =
          await _run([_rosterFile, applyFile.path, '-out:$outSave']);
      expect(applyResult.exitCode, 0,
          reason: 'apply failed:\n${applyResult.stderr}');
      expect(applyResult.stderr, isNot(contains('error')),
          reason: 'unexpected apply error:\n${applyResult.stderr}');

      // ── Step 4: re-export and verify ───────────────────────────────────────
      final reResult = await _run([outSave, '-td']);
      expect(reResult.exitCode, 0,
          reason: 're-export failed:\n${reResult.stderr}');

      final reLines = (reResult.stdout as String).trim().split('\n');
      final newNinerLine = reLines.firstWhere(
          (l) => l.startsWith('TeamData,49ers,'),
          orElse: () => throw StateError('No 49ers row in re-exported output'));
      final newParts = _splitTdRow(newNinerLine);

      expect(newParts[iNick],   equals(bearParts[iNick]),
          reason: 'Nickname should match Bears after copy');
      expect(newParts[iCity],   equals(bearParts[iCity]),
          reason: 'City should match Bears after copy');
      expect(newParts[iBook],   equals(bearParts[iBook]),
          reason: 'Playbook should match Bears after copy');
      //expect(newParts[iJersey], equals(bearParts[iJersey]),
      //    reason: 'DefaultJersey should match Bears after copy');

      // Sanity: Bears row in the output file should be unchanged.
      final newBearLine = reLines.firstWhere(
          (l) => l.startsWith('TeamData,Bears,'),
          orElse: () => throw StateError('No Bears row in re-exported output'));
      expect(newBearLine, equals(bearLine),
          reason: 'Bears row should be unmodified after copying to 49ers');
    });

//    test('DefaultJersey round-trip: set 49ers jersey and read back via CLI', () async {
//      // ── Step 1: read current 49ers DefaultJersey ───────────────────────────
//      final exportResult = await _run([_rosterFile, '-td']);
//      expect(exportResult.exitCode, 0,
//          reason: 'export failed:\n${exportResult.stderr}');
//
//      final lines = (exportResult.stdout as String).trim().split('\n');
//      const int iJersey = 7;
//
//      final ninerLine = lines.firstWhere(
//          (l) => l.startsWith('TeamData,49ers,'),
//          orElse: () => throw StateError('No 49ers row in export'));
//      final bearLine = lines.firstWhere(
//          (l) => l.startsWith('TeamData,Bears,'),
//          orElse: () => throw StateError('No Bears row in export'));
//
//      final origJersey = _splitTdRow(ninerLine)[iJersey];
//      final bearJersey = _splitTdRow(bearLine)[iJersey];
//
//      // Pick a target value that differs from the current 49ers jersey.
//      final newJersey = (int.parse(origJersey) == 0) ? '1' : '0';
//
//      // ── Step 2: apply a single-field change ────────────────────────────────
//      const applyHeader = 'TeamDataKey=TeamData,Team,DefaultJersey';
//      final applyRow = 'TeamData,49ers,$newJersey';
//      final applyFile = File('${tmpDir.path}/jersey_change.txt')
//        ..writeAsStringSync('$applyHeader\n$applyRow\n');
//      final outSave = '${tmpDir.path}/out.dat';
//
//      final applyResult =
//          await _run([_rosterFile, applyFile.path, '-out:$outSave']);
//      expect(applyResult.exitCode, 0,
//          reason: 'apply failed:\n${applyResult.stderr}');
//
//      // ── Step 3: re-export and verify ───────────────────────────────────────
//      final reResult = await _run([outSave, '-td']);
//      expect(reResult.exitCode, 0,
//          reason: 're-export failed:\n${reResult.stderr}');
//
//      final reLines = (reResult.stdout as String).trim().split('\n');
//
//      final newNinerLine = reLines.firstWhere(
//          (l) => l.startsWith('TeamData,49ers,'),
//          orElse: () => throw StateError('No 49ers row in re-exported output'));
//      expect(_splitTdRow(newNinerLine)[iJersey], equals(newJersey),
//          reason: '49ers DefaultJersey should be $newJersey after apply');
//
//      // Bears jersey must be untouched.
//      final newBearLine = reLines.firstWhere(
//          (l) => l.startsWith('TeamData,Bears,'),
//          orElse: () => throw StateError('No Bears row in re-exported output'));
//      expect(_splitTdRow(newBearLine)[iJersey], equals(bearJersey),
//          reason: 'Bears DefaultJersey should be unchanged');
//    });

    /*test('DefaultJersey round-trip: export → apply same value → binary unchanged', () async {
      // Applying the same DefaultJersey value that is already in the save
      // should produce a file byte-identical to the original.
      final exportResult = await _run([_rosterFile, '-td']);
      expect(exportResult.exitCode, 0);

      final lines = (exportResult.stdout as String).trim().split('\n');
      const int iJersey = 7;

      // Build an apply file that re-sets every team's DefaultJersey to its
      // current value — a no-op round-trip.
      final applyLines = StringBuffer()
        ..writeln('TeamDataKey=TeamData,Team,DefaultJersey');
      for (final line in lines) {
        if (!line.startsWith('TeamData,')) continue;
        final parts = _splitTdRow(line);
        applyLines.writeln('TeamData,${parts[1]},${parts[iJersey]}');
      }

      final applyFile = File('${tmpDir.path}/jersey_roundtrip.txt')
        ..writeAsStringSync(applyLines.toString());
      final outSave = '${tmpDir.path}/out.dat';

      final applyResult =
          await _run([_rosterFile, applyFile.path, '-out:$outSave']);
      expect(applyResult.exitCode, 0,
          reason: 'apply failed:\n${applyResult.stderr}');

      final origBytes = File(_rosterFile).readAsBytesSync();
      final outBytes  = File(outSave).readAsBytesSync();
      expect(outBytes, equals(origBytes),
          reason: 'Re-applying identical DefaultJersey values should produce a byte-identical file');
    });
    */

    // ── Franchise variants ──────────────────────────────────────────────────
//    TODO: Fix DefaultJersey 
//    test('[franchise] DefaultJersey round-trip: set 49ers jersey and read back via CLI', () async {
//      final exportResult = await _run([_franchiseFile, '-td']);
//      expect(exportResult.exitCode, 0,
//          reason: 'export failed:\n${exportResult.stderr}');
//
//      final lines = (exportResult.stdout as String).trim().split('\n');
//      const int iJersey = 7;
//
//      final ninerLine = lines.firstWhere(
//          (l) => l.startsWith('TeamData,49ers,'),
//          orElse: () => throw StateError('No 49ers row in franchise export'));
//      final bearLine = lines.firstWhere(
//          (l) => l.startsWith('TeamData,Bears,'),
//          orElse: () => throw StateError('No Bears row in franchise export'));
//
//      final origJersey = _splitTdRow(ninerLine)[iJersey];
//      final bearJersey = _splitTdRow(bearLine)[iJersey];
//
//      final newJersey = (int.parse(origJersey) == 0) ? '1' : '0';
//
//      const applyHeader = 'TeamDataKey=TeamData,Team,DefaultJersey';
//      final applyFile = File('${tmpDir.path}/fran_jersey_change.txt')
//        ..writeAsStringSync('$applyHeader\nTeamData,49ers,$newJersey\n');
//      final outSave = '${tmpDir.path}/fran_out.dat';
//
//      final applyResult =
//          await _run([_franchiseFile, applyFile.path, '-out:$outSave']);
//      expect(applyResult.exitCode, 0,
//          reason: 'apply failed:\n${applyResult.stderr}');
//
//      final reResult = await _run([outSave, '-td']);
//      expect(reResult.exitCode, 0,
//          reason: 're-export failed:\n${reResult.stderr}');
//
//      final reLines = (reResult.stdout as String).trim().split('\n');
//
//      final newNinerLine = reLines.firstWhere(
//          (l) => l.startsWith('TeamData,49ers,'),
//          orElse: () => throw StateError('No 49ers row in re-exported franchise'));
//      expect(_splitTdRow(newNinerLine)[iJersey], equals(newJersey),
//          reason: '[franchise] 49ers DefaultJersey should be $newJersey after apply');
//
//      final newBearLine = reLines.firstWhere(
//          (l) => l.startsWith('TeamData,Bears,'),
//          orElse: () => throw StateError('No Bears row in re-exported franchise'));
//      expect(_splitTdRow(newBearLine)[iJersey], equals(bearJersey),
//          reason: '[franchise] Bears DefaultJersey should be unchanged');
//    });

    test('[franchise] DefaultJersey round-trip: export → apply same value → binary unchanged', () async {
      final exportResult = await _run([_franchiseFile, '-td']);
      expect(exportResult.exitCode, 0);

      final lines = (exportResult.stdout as String).trim().split('\n');
      const int iJersey = 7;

      final applyLines = StringBuffer()
        ..writeln('TeamDataKey=TeamData,Team,DefaultJersey');
      for (final line in lines) {
        if (!line.startsWith('TeamData,')) continue;
        final parts = _splitTdRow(line);
        applyLines.writeln('TeamData,${parts[1]},${parts[iJersey]}');
      }

      final applyFile = File('${tmpDir.path}/fran_jersey_roundtrip.txt')
        ..writeAsStringSync(applyLines.toString());
      final outSave = '${tmpDir.path}/fran_out.dat';

      final applyResult =
          await _run([_franchiseFile, applyFile.path, '-out:$outSave']);
      expect(applyResult.exitCode, 0,
          reason: 'apply failed:\n${applyResult.stderr}');

      final origBytes = File(_franchiseFile).readAsBytesSync();
      final outBytes  = File(outSave).readAsBytesSync();
      expect(outBytes, equals(origBytes),
          reason: '[franchise] Re-applying identical DefaultJersey values should produce a byte-identical file');
    });
  });
}
