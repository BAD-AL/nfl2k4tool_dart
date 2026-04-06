import 'dart:typed_data';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'package:test/test.dart';

void main() {
  group('RosterKey.parse', () {
    test('parses comma-separated fields preserving order', () {
      final key = RosterKey.parse('Position,JerseyNumber,fname,lname');
      expect(key.fields, ['Position', 'JerseyNumber', 'fname', 'lname']);
    });

    test('field names are preserved as-given (not lowercased)', () {
      final key = RosterKey.parse('Speed,AGILITY,Strength');
      expect(key.fields, ['Speed', 'AGILITY', 'Strength']);
    });

    test('trims whitespace around field names', () {
      final key = RosterKey.parse(' Position , fname , lname ');
      expect(key.fields, ['Position', 'fname', 'lname']);
    });

    test('throws on empty string', () {
      expect(() => RosterKey.parse(''), throwsArgumentError);
    });

    test('throws on unknown field', () {
      expect(
        () => RosterKey.parse('Position,BOGUS'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message, 'message', contains('BOGUS'))),
      );
    });

    test('accepts all ability field names', () {
      const abilities = [
        'Speed', 'Agility', 'Strength', 'Jumping', 'Coverage', 'PassRush',
        'RunCoverage', 'PassBlocking', 'RunBlocking', 'Catch', 'RunRoute',
        'BreakTackle', 'HoldOntoBall', 'PowerRunStyle', 'PassAccuracy',
        'PassArmStrength', 'PassReadCoverage', 'Tackle', 'KickPower',
        'KickAccuracy', 'Stamina', 'Durability', 'Leadership', 'Scramble',
        'Composure', 'Consistency', 'Aggressiveness',
      ];
      expect(() => RosterKey.parse(abilities.join(',')), returnsNormally);
    });

    test('accepts all appearance field names', () {
      const appearance = [
        'BodyType', 'Skin', 'Face', 'Dreads', 'Helmet', 'FaceMask', 'Visor',
        'EyeBlack', 'MouthPiece', 'LeftGlove', 'RightGlove',
        'LeftWrist', 'RightWrist', 'LeftElbow', 'RightElbow',
        'Sleeves', 'LeftShoe', 'RightShoe', 'NeckRoll', 'Turtleneck',
      ];
      expect(() => RosterKey.parse(appearance.join(',')), returnsNormally);
    });
  });

  group('RosterKey built-in defaults', () {
    test('abilities key starts with identity fields', () {
      expect(RosterKey.abilities.fields.take(4).toList(),
          ['Position', 'fname', 'lname', 'JerseyNumber']);
    });

    test('appearance key starts with identity fields', () {
      expect(RosterKey.appearance.fields.take(4).toList(),
          ['Position', 'fname', 'lname', 'JerseyNumber']);
    });

    test('all key contains every field from abilities and appearance', () {
      final allFields = RosterKey.all.fields.toSet();
      for (final f in RosterKey.abilities.fields) {
        expect(allFields, contains(f), reason: '$f missing from all key');
      }
      for (final f in RosterKey.appearance.fields) {
        expect(allFields, contains(f), reason: '$f missing from all key');
      }
    });
  });

  group('RosterKey drives PlayerRecord.getAttribute', () {
    late Uint8List buf;
    late PlayerRecord p;

    setUp(() {
      buf = Uint8List(0x011500);
      p = PlayerRecord(buf, kBase + kPlayerStartGd);
      p.positionIndex = 0; // QB
      p.jerseyNumber = 5;
      p.setAbility('Speed', 87);
      p.setAbility('Agility', 72);
    });

    test('getAttribute returns correct value for each key field', () {
      final key = RosterKey.parse('Position,JerseyNumber,Speed,Agility');
      final values = key.fields.map((f) => p.getAttribute(f)).toList();
      expect(values, ['QB', '5', '87', '72']);
    });

    test('key field order controls column order', () {
      final key1 = RosterKey.parse('Speed,Agility');
      final key2 = RosterKey.parse('Agility,Speed');
      expect(key1.fields.map(p.getAttribute).toList(), ['87', '72']);
      expect(key2.fields.map(p.getAttribute).toList(), ['72', '87']);
    });
  });
}
