/// Example API usage for nfl2k4tool_dart — text-in / text-out workflow.
///
/// The typical browser flow:
///   1. User supplies file bytes (via FileReader or drag-drop)
///   2. Export data as text  →  display/edit in UI
///   3. Import edited text   →  apply back to save
///   4. Return modified bytes for download
///
/// File I/O is NOT part of the library.  The examples below use dart:io just
/// to run from the command line:
///   dart API/exampleApi.dart path/to/savegame.dat
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart API/exampleApi.dart <savegame.dat|.zip>');
    exit(1);
  }

  // -------------------------------------------------------------------------
  // 1. Load — caller supplies bytes; the library does the rest.
  // -------------------------------------------------------------------------

  final Uint8List bytes = File(args[0]).readAsBytesSync();
  final save = NFL2K4Gamesave.fromBytes(bytes);
  // Or use the embedded unmodified base roster (no file needed):
  // final save = NFL2K4Gamesave.fromBaseRoster();

  print('isFranchise: ${save.isFranchise}');
  print('isZip:       ${save.isZip}');

  // -------------------------------------------------------------------------
  // 2. Choose a RosterKey — controls which player fields appear in text I/O.
  // -------------------------------------------------------------------------

  // Pre-built keys:
  //   RosterKey.abilities   — ratings + scalar attributes (Speed, Catch, etc.)
  //   RosterKey.appearance  — visual attributes (BodyType, Skin, Face, gear…)
  //   RosterKey.all         — abilities + appearance combined

  // Custom key — only the fields you care about:
  final customKey = RosterKey.parse('Position,fname,lname,Speed,Catch,PassAccuracy');

  // -------------------------------------------------------------------------
  // 3. Export player data as text.
  // -------------------------------------------------------------------------

  // Full roster, abilities only (default key).
  final abilitiesText = save.toText(RosterKey.abilities);

  // Single team by index (kTeamNames is alphabetical: 0=49ers, 1=Bears, …).
  final eaglesIndex = kTeamNames.indexOf('Eagles');
  final eaglesText  = save.toText(RosterKey.abilities, teamIndex: eaglesIndex);

  // Include free agents in the output.
  final withFaText = save.toText(RosterKey.abilities, includeFreeAgents: true);

  // Custom fields, 49ers only.
  final ninerIndex  = kTeamNames.indexOf('49ers');
  final customText  = save.toText(customKey, teamIndex: ninerIndex);

  print('\n[abilities export — first 4 lines]');
  abilitiesText.split('\n').take(4).forEach(print);

  print('\n[Eagles export — first 4 lines]');
  eaglesText.split('\n').take(4).forEach(print);

  print('\n[custom key export — first 4 lines]');
  customText.split('\n').take(4).forEach(print);

  // -------------------------------------------------------------------------
  // 4. Export coach / team data as text.
  // -------------------------------------------------------------------------

  // Coach data — all 32 teams.
  final coachText = save.toCoachDataText();
  print('\n[coach export — first 4 lines]');
  coachText.split('\n').take(4).forEach(print);

  // Team metadata (Nickname, City, Abbrev, Playbook, …).
  final teamText = save.toTeamDataText();
  print('\n[team export — first 4 lines]');
  teamText.split('\n').take(4).forEach(print);

  // Schedule (franchise saves only).
  if (save.isFranchise) {
    final schedText = scheduleToText(save.getSchedule());
    print('\n[schedule export — first 4 lines]');
    schedText.split('\n').take(4).forEach(print);
  }

  // -------------------------------------------------------------------------
  // 5. Import — apply edited text back to the save.
  //
  // The text format exported above is the same format InputParser consumes.
  // The #header line (or a Key= directive) tells InputParser which fields are
  // present; only supplied fields are changed — everything else is untouched.
  // -------------------------------------------------------------------------

  // Round-trip: export → (user edits in UI) → apply back.
  // Here we simulate an edit by modifying one value in the exported text
  // before passing it to InputParser.  In a web app the user edits the
  // textarea directly; the format is identical.
  //
  // Only the fields in the #header need to be present per row — everything
  // else on each player record is left untouched.
  final editedText = eaglesText.replaceFirstMapped(
    RegExp(r'^(QB,.+?,McNabb,.*?),(\d+),', multiLine: true),
    (m) => '${m[1]},99,',   // bump McNabb's Speed to 99
  );

  final playerResult = InputParser(save).applyText(editedText, key: RosterKey.abilities);
  print('\nPlayer patch: ${playerResult.updated} updated, '
      '${playerResult.skipped} skipped');
  if (playerResult.errors.isNotEmpty) {
    print('Errors:\n  ${playerResult.errors.join('\n  ')}');
  }

  // Applying coach data — same pattern.
  final coachResult = InputParser(save).applyText(coachText);
  print('Coach patch:  ${coachResult.updated} updated');

  // Applying team data.
  final teamResult = InputParser(save).applyText(teamText);
  print('Team patch:   ${teamResult.updated} updated');

  // Applying schedule (franchise only).
  if (save.isFranchise) {
    final schedResult = InputParser(save).applyText(
        scheduleToText(save.getSchedule()));
    print('Sched patch:  ${schedResult.updated} updated');
  }

  // -------------------------------------------------------------------------
  // 6. Save — return bytes to the caller; they decide how to persist/download.
  // -------------------------------------------------------------------------

  // Raw .dat bytes (re-signed, ready to write or send as a download).
  final Uint8List outBytes = save.toBytes();
  print('\nOutput: ${outBytes.length} bytes');

  // If the save was originally a ZIP (Xbox VSAV), re-pack it:
  // final Uint8List zipBytes = save.toZipBytes();

  // CLI — write to disk:
  // File('out.dat').writeAsBytesSync(save.toBytes());

  // Web — trigger a browser download (dart:html / package:web):
  // final blob = Blob([save.toBytes()]);
  // final url  = Url.createObjectUrlFromBlob(blob);
  // AnchorElement(href: url)
  //   ..setAttribute('download', 'roster_edited.dat')
  //   ..click();
  // Url.revokeObjectUrl(url);
}
