import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'package:test/test.dart';

void main() {
  group('HMAC-SHA1 signing', () {
    const saveFiles = {
      'roster':    'test/test_files/base_roster_2k4_savegame.dat',
      'franchise': 'test/test_files/base_franchise_2k4_savegame.dat',
    };

    for (final entry in saveFiles.entries) {
      final label = entry.key;
      final path  = entry.value;

      test('stored signature matches recomputed signature [$label]', () {
        final data = File(path).readAsBytesSync();

        final stored   = data.sublist(kSignatureOffset,
                                      kSignatureOffset + kSignatureLength);
        final toSign   = data.sublist(kSignatureOffset + kSignatureLength);
        final computed = Hmac(sha1, kXboxSignKey).convert(toSign).bytes;

        expect(computed, equals(stored),
            reason: '$label: stored HMAC-SHA1 does not match recomputed value');
      });
    }
  });
}
