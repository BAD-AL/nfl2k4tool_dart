import 'dart:io';
import 'package:test/test.dart';

const _saveFile = 'test/test_files/base_franchise_2k4_savegame.dat';
const _bin = 'bin/nfl2k4tool_dart.dart';

Future<ProcessResult> _run(List<String> args) =>
    Process.run('dart', ['run', _bin, ...args]);

void main() {
  group('CLI -key=', () {
    test('header matches exactly the key fields in order', () async {
      final result = await _run([_saveFile, '-key=Position,JerseyNumber,fname,lname']);
      expect(result.exitCode, 0);
      final lines = (result.stdout as String).split('\n');
      final header = lines.firstWhere((l) => l.startsWith('#'));
      // Header should be exactly '#Position,JerseyNumber,fname,lname,'
      expect(header, '#Position,JerseyNumber,fname,lname,');
    });

    test('data rows have same number of columns as key', () async {
      final result = await _run([_saveFile, '-key=Position,fname,lname,Speed,Agility']);
      expect(result.exitCode, 0);
      final dataLines = (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('Team ='))
          .toList();
      expect(dataLines, isNotEmpty);
      for (final line in dataLines) {
        // Each row ends with a trailing comma; split gives fields+1 empty tail
        final cols = line.split(',');
        expect(cols.length, 6, // 5 fields + trailing empty
            reason: 'Wrong column count in: $line');
      }
    });

    test('-key combined with -team= filters to one team', () async {
      final result = await _run([_saveFile, '-key=Position,fname,lname', '-team=49ers']);
      expect(result.exitCode, 0);
      final output = result.stdout as String;
      expect(output, contains('Team = 49ers'));
      // No other team header should appear
      expect(output, isNot(contains('Team = Bears')));
    });

    test('unknown field name exits with error', () async {
      final result = await _run([_saveFile, '-key=Position,BOGUS']);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('BOGUS'));
    });

    test('-ab output is unchanged when no -key is given (header starts with #Position)', () async {
      final result = await _run([_saveFile, '-ab', '-team=49ers']);
      expect(result.exitCode, 0);
      final lines = (result.stdout as String).split('\n');
      final header = lines.firstWhere((l) => l.startsWith('#'));
      expect(header, startsWith('#Position,fname,lname,JerseyNumber,'));
    });
  });
}
