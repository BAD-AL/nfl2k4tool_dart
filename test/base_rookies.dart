import 'dart:io';
import 'dart:typed_data';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';
import 'test_helpers.dart';

void main() {
  final data = File('test/test_files/base_franchise_2k4_savegame.dat').readAsBytesSync();
  final save = loadFile('test/test_files/base_franchise_2k4_savegame.dat');
  const base = 0x1E0;
  final bd = ByteData.sublistView(data);

  // Count rookies per team
  for (int t = 0; t < 34; t++) {
    final players = save.getTeamPlayers(t);
    final rookies = players.where((p) => p.yearsPro == 1).toList();
    if (rookies.isNotEmpty) {
      print('Team ${kTeamNames[t]} (idx $t): ${rookies.length} rookie(s)');
      for (final r in rookies.take(2)) {
        final fnRel = bd.getInt32(r.fileOffset + 0x10, Endian.little);
        print('  fn="${r.firstName}" ln="${r.lastName}" pos=${r.position} fn_rel=$fnRel recFile=0x${r.fileOffset.toRadixString(16)}');
      }
    }
  }

  // Check FA pool  
  final fa = save.getFreeAgentPlayers();
  final faRookies = fa.where((p) => p.yearsPro == 1).toList();
  print('\nFA rookies: ${faRookies.length}');
  for (final r in faRookies.take(3)) {
    final fnRel = bd.getInt32(r.fileOffset + 0x10, Endian.little);
    print('  fn="${r.firstName}" ln="${r.lastName}" pos=${r.position} fn_rel=$fnRel');
  }
  
  // Check the DraftClass team slot (index 33)
  print('\nDraftClass slot (idx 33): ${save.getTeamPlayers(33).length} players');
  for (final p in save.getTeamPlayers(33).take(5)) {
    final fnRel = bd.getInt32(p.fileOffset + 0x10, Endian.little);
    print('  fn="${p.firstName}" ln="${p.lastName}" pos=${p.position} fn_rel=$fnRel recFile=0x${p.fileOffset.toRadixString(16)}');
  }
}
