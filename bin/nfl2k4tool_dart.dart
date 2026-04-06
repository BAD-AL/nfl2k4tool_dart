import 'dart:io';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';

// ---------------------------------------------------------------------------
// File I/O helpers (dart:io layer — not part of the library)
// ---------------------------------------------------------------------------

NFL2K4Gamesave _loadFile(String path) =>
    NFL2K4Gamesave.fromBytes(File(path).readAsBytesSync());

void _saveFile(NFL2K4Gamesave save, String path) {
  final isZipOut = path.toLowerCase().endsWith('.zip');
  if (isZipOut || (save.isZip && !path.toLowerCase().endsWith('.dat'))) {
    File(path).writeAsBytesSync(save.toZipBytes());
  } else {
    File(path).writeAsBytesSync(save.toBytes());
  }
}


// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
void main(List<String> args) {
    if (args.isEmpty) {
    _printUsage();
    exit(0);
  }
  String result = runMain(args);
  if(result == "1"){
    exit(1);
  }
  print(result);
}

// When this returns "1" that is an error indication that exit(1) should be called
// during normal CLI operation
String runMain(List<String> args) {

  String? saveFileName;
  String? outputFileName;  // should only be one of the following [.dat, .zip] // PS2 support coming later.
  String? dataToApplyFile;
  bool showAbilities = false;
  bool showAppearance = false;
  bool showFreeAgents = false;
  bool seqDump = false;
  bool showSchedule = false;
  bool showTeamData = false;
  bool showCoachData = false;
  bool showAllStarTeams = false;
  bool showPlayerControlled = false;
  bool sortPos = false;
  bool krCheck = false;
  bool fixKr = false;
  bool fixSkin = false;
  bool vrabelFix = false;
  bool showTime = false;
  String? teamFilter;
  String? keyArg;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('-out:')) {
      outputFileName = a.substring(5);
    } else if (a == '-ab') {
      showAbilities = true;
    } else if (a == '-app') {
      showAppearance = true;
    } else if (a == '-fa') {
      showFreeAgents = true;
    } else if (a == '-seq') {
      seqDump = true;
    } else if (a == '-sch') {
      showSchedule = true;
    } else if (a == '-td') {
      showTeamData = true;
    } else if (a == '-coach') {
      showCoachData = true;
    } else if (a == '-allstar') {
      showAllStarTeams = true;
    } else if (a == '-pc') {
      showPlayerControlled = true;
    } else if (a == '-sortpos') {
      sortPos = true;
    } else if (a == '-krcheck') {
      krCheck = true;
    } else if (a == '-fixkr') {
      fixKr = true;
    } else if (a == '-fixskin') {
      fixSkin = true;
    } else if (a == '-vrabelfix') {
      vrabelFix = true;
    } else if (a == '-time') {
      showTime = true;
    } else if (a.startsWith('-team=')) {
      teamFilter = a.substring(6);
    } else if (a.startsWith('-key=')) {
      keyArg = a.substring(5);
    } else if (a == '-help' || a == '--help' || a == '/?' || a == '/help') {
      _printUsage();
      exit(0);
    } else if (!a.startsWith('-') && saveFileName == null) {
      saveFileName = a;
    } else if (!a.startsWith('-') && saveFileName != null) {
      dataToApplyFile = a;
    }
  }

  bool usingBaseRoster = false;
  if (saveFileName == null) {
    stderr.writeln('No save file specified — using embedded base roster.');
    usingBaseRoster = true;
  }

  // Resolve the active RosterKey.
  // -key=... overrides -ab/-app entirely.
  // Otherwise fall back to -ab/-app (default: abilities only).
  RosterKey activeKey;
  if (keyArg != null) {
    try {
      activeKey = RosterKey.parse(keyArg);
    } on ArgumentError catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    }
  } else {
    if (showAbilities && showAppearance) {
      activeKey = RosterKey.all;
    } else if (showAppearance) {
      activeKey = RosterKey.appearance;
    } else {
      activeKey = RosterKey.abilities;
    }
  }

  // Resolve -team=xxx to a team index (or -1 for FA).
  int? resolvedTeamIndex;
  if (teamFilter != null) {
    final q = teamFilter.toLowerCase();
    if (q == 'fa' || q == 'freeagents' || q == 'free agents') {
      resolvedTeamIndex = -1; // sentinel for FA
      showFreeAgents = true;
    } else {
      for (int i = 0; i < kTeamNames.length; i++) {
        if (kTeamNames[i].toLowerCase().contains(q)) {
          resolvedTeamIndex = i;
          break;
        }
      }
      if (resolvedTeamIndex == null) {
        stderr.writeln('Unknown team: "$teamFilter"');
        stderr.writeln('Known teams: ${kTeamNames.join(', ')}');
        exit(1);
      }
    }
  }

  try {
    final save = usingBaseRoster
        ? NFL2K4Gamesave.fromBaseRoster()
        : _loadFile(saveFileName!);

    if (seqDump) {
      // Sequential dump: walk player array in memory order, skip blank records.
      final output = _buildSeqOutput(save, activeKey);
      return output;
    }

    if (sortPos) {
      if (outputFileName == null) {
        stderr.writeln('Error: -out:<file> required when using -sortpos.');
        return "1";
      }
      save.sortAllTeamsPlayersByPosition();
      _saveFile(save, outputFileName);
      print('Position sort applied and saved to $outputFileName');
    }

    if (fixKr) {
      if (outputFileName == null) {
        stderr.writeln('Error: -out:<file> required when using -fixkr.');
        return "1";
      }
      save.fixKrPrWithCbs();
      _saveFile(save, outputFileName);
      print('KR/PR fix applied and saved to $outputFileName');
      return "";
    }

    if (fixSkin) {
      if (outputFileName == null) {
        stderr.writeln('Error: -out:<file> required when using -fixskin.');
        return "1";
      }
      final count = save.autoFixSkinFromPhoto();
      _saveFile(save, outputFileName);
      print('Skin/face fix applied: $count players updated. Saved to $outputFileName');
      return "";
    }

    StringBuffer sb =StringBuffer();
    if (krCheck) {
      final warnings = save.checkKrPrPositions();
      
      if (warnings.isEmpty) {
        print('All KR/PR slots have valid returner positions.');
      } else {
        for (final w in warnings) {
          sb.writeln(w);
        }
      }
      return sb.toString();
    }

    // write out team players
    if(showAppearance || showAbilities || keyArg != null ){
      final output = _buildOutput(
          save, activeKey, showFreeAgents,
          teamIndex: resolvedTeamIndex,
          includeAllStarTeams: showAllStarTeams);
      sb.write(output);
      sb.writeln();
    }

    if (showCoachData) {
      sb.write(save.toCoachDataText());
      sb.writeln();
    }

    if (showTeamData) {
      if (showPlayerControlled) {
        if (!save.isFranchise) {
          stderr.writeln('Warning: -pc requires a franchise save; PlayerControlled skipped.');
        } else {
          final teams = save.getPlayerControlledTeams();
          sb.writeln('PlayerControlled=[${teams.join(',')}]');
          sb.writeln('# PlayerControlledTeams=${teams.length}');
          sb.writeln();
        }
      }
      sb.write(save.toTeamDataText());
      sb.writeln();
    }

    if (showSchedule) {
      if (!save.isFranchise) {
        stderr.writeln('Error: -sch requires a franchise save file.');
        return "1";
      }
      // Export schedule.
      String output = scheduleToText(save.getSchedule(), includeTime: showTime);
      sb.write(output);
      sb.writeln();
    }

    // User specified some data to process.
    if (dataToApplyFile != null) {
      // Import mode: apply text data, then save
      if (outputFileName == null) {
        stderr.writeln('Error: -out:<file> required when applying data.');
        return "1";
      }
      _applyData(save, dataToApplyFile, activeKey);
      if (vrabelFix) {
        save.vrabelFix();
        print('vrabelFix: Vrabel restored from base roster.');
      }
      _saveFile(save, outputFileName);
      print('Saved to $outputFileName');
      return sb.toString();
    }

    if (vrabelFix) {
      if (outputFileName == null) {
        stderr.writeln('Error: -out:<file> required when using -vrabelfix.');
        return "1";
      }
      save.vrabelFix();
      _saveFile(save, outputFileName);
      print('vrabelFix: Vrabel restored from base roster. Saved to $outputFileName');
      return "";
    }

    return sb.toString();
  } on FileSystemException catch (e) {
    stderr.writeln('File error: $e');
    return "1";
  } on FormatException catch (e) {
    stderr.writeln('Format error: $e');
    return "1";
  }
}

// ---------------------------------------------------------------------------
// Output builder
// ---------------------------------------------------------------------------

String _buildOutput(NFL2K4Gamesave save, RosterKey key, bool showFa,
    {int? teamIndex, bool includeAllStarTeams = false}) =>
    save.toText(key,
        teamIndex: teamIndex,
        includeFreeAgents: showFa,
        includeAllStarTeams: includeAllStarTeams);

// ---------------------------------------------------------------------------
// Sequential (array-order) dump
// ---------------------------------------------------------------------------

String _buildSeqOutput(NFL2K4Gamesave save, RosterKey key) {
  final data = save.bytes;
  final buf = StringBuffer();

  // Header: SeqIndex prefix + key fields.
  buf.write('#SeqIndex,');
  for (final f in key.fields) {
    buf.write('$f,');
  }
  buf.writeln();

  final base = save.base;
  int printed = 0;
  int slot = 0;
  while (slot < kMaxPlayerSlot) {
    final recFile = base + kPlayerStartGd + slot * kPlayerStride;
    if (recFile + 0x53 > data.length) break;

    final p = PlayerRecord(data, recFile, base);
    if (p.firstName.isEmpty && p.lastName.isEmpty) {
      slot++;
      continue;
    }

    buf.write('$slot,');
    for (final f in key.fields) {
      buf.write('${_csvVal(p.getAttribute(f))},');
    }
    buf.writeln();
    printed++;
    slot++;
  }

  stderr.writeln('$printed player records written.');
  return buf.toString();
}

String _csvVal(String s) {
  // Only quote if the value contains a comma (matches 2K5 tool behaviour).
  // Heights like 6'0" are output unquoted.
  if (s.contains(',')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

// ---------------------------------------------------------------------------
// Import / apply
// ---------------------------------------------------------------------------

// generally we would have the Key Specified by the dataFile, 
// but it's also possible to specify the key on the command line
// in the _applyData case, it's wonky to do it this way, but I'll allow it.
void _applyData(NFL2K4Gamesave save, String dataFile, RosterKey key) {
  final text = File(dataFile).readAsStringSync();
  if (text.trim().isEmpty) {
    stderr.writeln('Data file is empty.');
    return;
  }
  // key is passed as the fallback; the file's own #header or Key= directive
  // takes precedence inside InputParser.
  final result = InputParser(save).applyText(text, key: key);
  for (final e in result.errors) {
    stderr.writeln(e);
  }
  print('Applied: ${result.updated} updated, ${result.skipped} skipped.');
}

// ---------------------------------------------------------------------------

void _printUsage() {
  print('''
NFL 2K4 Gamesave Tool

Usage:
  dart run bin/nfl2k4tool_dart.dart <savefile> [flags] [-out:<outfile>] [datafile]

Flags:
  -ab          Output abilities + scalar attributes
  -app         Output appearance attributes
               (default: -ab if neither specified; -ab -app for all)
  -fa          Include Free Agents (players not assigned to any team)
  -allstar     Include non-NFL teams: Challengers, Swamis, Alumni, All AFC/NFC/NFL
  -team=xxx    Only output the named team (case-insensitive partial match).
               Use -team=fa for Free Agents.
  -key=f1,f2   Output exactly the listed fields in that order.
               Overrides -ab/-app. Field names are case-insensitive.
  -coach       Export coach data (FirstName, LastName, Info1-3, Body, Photo, Wins, Losses, ...)
               Use with a data file to import coach data.
  -sch         Export or import the schedule (franchise saves only)
  -td          Export team data (Nickname, Abbrev, City, AbbrAlt, Playbook[, PlayerControlled])
  -pc          Prefix team data output with PlayerControlled=[team1,...] line (franchise only)
  -sortpos     Reorder each team's player slots by position group (post-apply KR/PR fix)
               Requires -out:<file>.
  -krcheck     Check KR/PR slots for invalid returner positions (not CB/SS/FS/RB/FB/WR)
  -fixkr       Fix invalid KR/PR slots by rotating last CBs into those slots
               Requires -out:<file>. Run after -sortpos.
  -fixskin     Fix Skin and Face for any player whose Photo matches a base-roster
               entry but whose Skin/Face doesn't match. Requires -out:<file>.
  -vrabelfix   [TEMP DEBUG] After data apply, restore Mike Vrabel from the base
               roster into his Patriots slot. Requires -out:<file>.
  -time        Include date/time in schedule export (e.g. "jets at bears ; 09-07-2003-01-00")
  -seq         Dump all players in raw array order (debug/research use)
  -out:<file>  Write output to file instead of stdout
               Required when applying a data file or schedule.

Examples:
  # Export all player data to a text file
  dart run bin/nfl2k4tool_dart.dart roster.dat -ab -app -out:players.txt

  # Export just the 49ers
  dart run bin/nfl2k4tool_dart.dart roster.dat -ab -team=49ers

  # Export specific fields for all players
  dart run bin/nfl2k4tool_dart.dart roster.dat -key=Position,JerseyNumber,fname,lname,Speed,Agility

  # Apply a modified text file back to the save
  dart run bin/nfl2k4tool_dart.dart roster.dat -ab -app players_edited.txt -out:roster_new.dat

  # Export abilities including free agents
  dart run bin/nfl2k4tool_dart.dart roster.dat -ab -fa -out:abilities.txt
''');
}
