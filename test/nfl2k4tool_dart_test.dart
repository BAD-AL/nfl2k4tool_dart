import 'dart:typed_data';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'package:test/test.dart';

void main() {
  group('PlayerRecord bit packing', () {
    late Uint8List buf;
    late PlayerRecord p;

    setUp(() {
      // Minimal buffer: BASE (0x18) + enough room for one player record past kPlayerStartGd
      // kBase=0x18, kPlayerStartGd=0x0113A4 → file offset 0x0113BC
      // Record extends to +0x52, so we need 0x0113BC + 0x53 = 0x01140F bytes
      buf = Uint8List(0x011500);
      // Plant valid fname/lname relative pointers pointing to a null string
      // (pointer at +0x10 and +0x14 relative to record start)
      // We'll just leave them pointing to nearby nulls — not tested here
      p = PlayerRecord(buf, kBase + kPlayerStartGd);
    });

    test('abilities round-trip', () {
      p.setAbility('Speed', 87);
      expect(p.getAbility('Speed'), 87);
      p.setAbility('Aggressiveness', 55);
      expect(p.getAbility('Aggressiveness'), 55);
    });

    test('jersey number round-trip', () {
      p.jerseyNumber = 23;
      expect(p.jerseyNumber, 23);
      p.jerseyNumber = 0;
      expect(p.jerseyNumber, 0);
    });

    test('skin round-trip', () {
      for (int v = 0; v <= 5; v++) {
        p.skin = v;
        expect(p.skin, v, reason: 'skin=$v');
      }
    });

    test('body round-trip', () {
      for (int v = 0; v <= 3; v++) {
        p.body = v;
        expect(p.body, v, reason: 'body=$v');
      }
    });

    test('elbows round-trip', () {
      p.leftElbow = 5;
      p.rightElbow = 3;
      expect(p.leftElbow, 5);
      expect(p.rightElbow, 3);
    });

    test('left/right glove round-trip', () {
      p.leftGlove = 7;
      p.rightGlove = 3;
      expect(p.leftGlove, 7);
      expect(p.rightGlove, 3);
    });

    test('left/right wrist round-trip', () {
      p.leftWrist = 9;
      p.rightWrist = 5;
      expect(p.leftWrist, 9);
      expect(p.rightWrist, 5);
    });

    test('hand bit does not clobber body bits', () {
      p.body = 2;
      p.eyeBlack = 1;
      p.hand = 1;
      p.dreads = 0;
      expect(p.body, 2);
      expect(p.eyeBlack, 1);
      expect(p.hand, 1);
    });

    test('dob round-trip', () {
      p.dob = (year: 1978, month: 3, day: 15);
      final d = p.dob;
      expect(d.year, 1978);
      expect(d.month, 3);
      expect(d.day, 15);
    });

    test('weight/height round-trip', () {
      p.weight = 225;
      p.height = 74;
      expect(p.weight, 225);
      expect(p.height, 74);
    });

    test('position round-trip', () {
      p.positionIndex = 7; // RB
      expect(p.position, 'RB');
    });

    test('visor round-trip (all values)', () {
      for (int v = 0; v <= 2; v++) {
        p.visor = v;
        expect(p.visor, v, reason: 'visor=$v');
      }
    });

    test('visor does not clobber faceMask or face', () {
      p.faceMask = 12;
      p.face = 7;
      p.visor = 1; // Clear — sets bit7 of +0x21, bit0 of +0x22
      expect(p.faceMask, 12, reason: 'faceMask clobbered by visor=1');
      expect(p.face, 7, reason: 'face clobbered by visor=1');
      expect(p.visor, 1);
      p.visor = 2; // Black — sets bit0 of +0x22, clears bit7 of +0x21
      expect(p.faceMask, 12, reason: 'faceMask clobbered by visor=2');
      expect(p.face, 7, reason: 'face clobbered by visor=2');
      expect(p.visor, 2);
    });

    test('faceMask/face do not clobber visor', () {
      p.visor = 1; // Clear
      p.faceMask = 5;
      p.face = 3;
      expect(p.visor, 1, reason: 'visor clobbered by faceMask/face writes');
    });
  });
}
