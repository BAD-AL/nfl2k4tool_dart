import 'constants.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// GD offset of the first schedule game slot (franchise saves only).
/// Confirmed by pattern-matching Week 1 games at file offset 0x9B663
/// (franchise base = 0x1E0, so GD = 0x9B483).
const int kScheduleGd = 0x9B483;

const int kScheduleWeeks = 17;
const int kScheduleGamesPerWeek = 16;

/// Hard cap on games per week for each of the 17 weeks.
/// Weeks 1–2 and 11–17 support 16 games; weeks 3–10 support 14.
/// Confirmed from NFL2K5Tool's ReLayoutScheduleWeeks reference implementation.
const List<int> kGamesPerWeek = [
  16, 16,                          // weeks 1–2
  14, 14, 14, 14, 14, 14, 14, 14, // weeks 3–10
  16, 16, 16, 16, 16, 16, 16,     // weeks 11–17
];

/// Bytes per game slot; layout: home(0), away(1), month(2), day(3),
/// year-2000(4), hour(5), minute(6), flags(7).
const int kScheduleGameStride = 8;

/// An empty/bye slot: 8 zero bytes.
const List<int> kNullGameBytes = [0, 0, 0, 0, 0, 0, 0, 0];

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One scheduled game.
class ScheduleGame {
  /// Team index (0–31, same order as [kTeamNames]) of the home team.
  final int homeTeam;

  /// Team index of the away team.
  final int awayTeam;

  final int month;       // 1–12
  final int day;         // 1–31
  final int year;        // 2-digit (e.g. 3 = 2003)
  final int hour;        // 0–23
  final int minute;      // 0–59

  const ScheduleGame({
    required this.homeTeam,
    required this.awayTeam,
    required this.month,
    required this.day,
    required this.year,
    required this.hour,
    required this.minute,
  });

  /// Returns the home team name in lowercase (e.g. `'redskins'`).
  String get homeName =>
      (homeTeam < kTeamNames.length ? kTeamNames[homeTeam] : 'team$homeTeam')
          .toLowerCase();

  /// Returns the away team name in lowercase (e.g. `'jets'`).
  String get awayName =>
      (awayTeam < kTeamNames.length ? kTeamNames[awayTeam] : 'team$awayTeam')
          .toLowerCase();

  /// Human-readable game string, e.g. "Jets at Redskins".
  @override
  String toString() => '$awayName at $homeName';

  /// Copy with replacement team indices (date fields unchanged).
  ScheduleGame withTeams(int newHome, int newAway) => ScheduleGame(
        homeTeam: newHome,
        awayTeam: newAway,
        month: month,
        day: day,
        year: year,
        hour: hour,
        minute: minute,
      );
}

// ---------------------------------------------------------------------------
// Text export
// ---------------------------------------------------------------------------

/// Formats a full 17-week schedule as human-readable text.
///
/// [weeks] is the list returned by [NFL2K4Gamesave.getSchedule].
/// Each inner list holds exactly [kScheduleGamesPerWeek] entries; `null`
/// means a bye slot.
String scheduleToText(List<List<ScheduleGame?>> weeks, {bool includeTime = false}) {
  final buf = StringBuffer();
  // Infer season year from the first non-null game.
  int? twoDigitYear;
  for (final wk in weeks) {
    for (final g in wk) {
      if (g != null) { twoDigitYear = g.year; break; }
    }
    if (twoDigitYear != null) break;
  }
  if (twoDigitYear != null) {
    buf.writeln('YEAR=${2000 + twoDigitYear}');
    buf.writeln();
  }

  for (int w = 0; w < weeks.length; w++) {
    final games = weeks[w].whereType<ScheduleGame>().toList();
    buf.writeln('Week ${w + 1}  [${games.length} games]');
    for (final g in games) {
      if (includeTime) {
        final mm = g.month.toString().padLeft(2, '0');
        final dd = g.day.toString().padLeft(2, '0');
        final yyyy = (2000 + g.year).toString();
        final hh = g.hour.toString().padLeft(2, '0');
        final min = g.minute.toString().padLeft(2, '0');
        buf.writeln('${g.toString()} ; $mm-$dd-$yyyy-$hh-$min');
      } else {
        buf.writeln(g.toString());
      }
    }
    buf.writeln();
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Text import
// ---------------------------------------------------------------------------

/// Result of parsing a schedule text.
class ScheduleParseResult {
  /// Parsed schedule: [kScheduleWeeks] weeks, each with [kScheduleGamesPerWeek]
  /// slots.  `null` = bye/empty.
  final List<List<ScheduleGame?>> weeks;
  final List<String> errors;
  ScheduleParseResult(this.weeks, this.errors);
}

/// Parses a schedule text (the format produced by [scheduleToText]) into a
/// list of weeks suitable for [NFL2K4Gamesave.setSchedule].
///
/// Uses a two-phase best-effort algorithm matching NFL2K5Tool behaviour:
///   Phase 1 — collect all game lines in file order (Week headers are ignored
///             for placement purposes).
///   Phase 2 — distribute games into weeks greedily using [kGamesPerWeek] as
///             the hard cap per week.  Games that exceed the total capacity
///             (sum of [kGamesPerWeek] = 256) are dropped with a warning.
///
/// [existing] is the schedule currently in the save file; it is used to fill
/// in date/time values for any game line that does not include them.
ScheduleParseResult parseScheduleText(
    String text, List<List<ScheduleGame?>> existing) {
  final errors = <String>[];

  // Build an empty 17-week skeleton filled with nulls.
  final weeks = List<List<ScheduleGame?>>.generate(
      kScheduleWeeks, (_) => List<ScheduleGame?>.filled(kScheduleGamesPerWeek, null));

  // ── Date/time helpers ────────────────────────────────────────────────────
  ScheduleGame? existingGame(int week, int slot) {
    if (week < existing.length && slot < existing[week].length) {
      return existing[week][slot];
    }
    return null;
  }

  ScheduleGame defaultGame(int week, int slot, int homeIdx, int awayIdx) {
    ScheduleGame? src = existingGame(week, slot);
    for (int s = slot - 1; src == null && s >= 0; s--) {
      src = existingGame(week, s);
    }
    if (src == null) {
      outer:
      for (final wk in existing) {
        for (final g in wk) {
          if (g != null) { src = g; break outer; }
        }
      }
    }
    return ScheduleGame(
      homeTeam: homeIdx,
      awayTeam: awayIdx,
      month:  src?.month  ?? 9,
      day:    src?.day    ?? 7,
      year:   src?.year   ?? 3,
      hour:   src?.hour   ?? 1,
      minute: src?.minute ?? 0,
    );
  }

  // ── Phase 1: collect all resolved games in file order ───────────────────
  int? textYear;
  final collected = <({int homeIdx, int awayIdx})>[];

  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    if (line.toLowerCase().startsWith('year=')) {
      final n = int.tryParse(line.substring(5).trim());
      if (n != null) textYear = n - 2000;
      continue;
    }

    // Week headers are intentionally ignored for game placement.
    if (RegExp(r'^week\b', caseSensitive: false).hasMatch(line)) continue;

    final m = RegExp(r'^(.+?)\s+at\s+(.+?)$', caseSensitive: false)
        .firstMatch(line);
    if (m != null) {
      final awayName = m.group(1)!.trim();
      final homeName = m.group(2)!.trim();
      final awayIdx  = _resolveTeam(awayName, errors);
      final homeIdx  = _resolveTeam(homeName, errors);
      if (awayIdx != null && homeIdx != null) {
        collected.add((homeIdx: homeIdx, awayIdx: awayIdx));
      }
    }
  }

  // ── Phase 2: distribute into weeks per kGamesPerWeek ────────────────────
  final capacity = kGamesPerWeek.fold(0, (a, b) => a + b);
  int gi = 0;
  for (int w = 0; w < kScheduleWeeks && gi < collected.length; w++) {
    for (int s = 0; s < kGamesPerWeek[w] && gi < collected.length; s++) {
      final g = collected[gi++];
      ScheduleGame game = defaultGame(w, s, g.homeIdx, g.awayIdx);
      if (textYear != null) {
        game = ScheduleGame(
          homeTeam: g.homeIdx,
          awayTeam: g.awayIdx,
          month:  game.month,
          day:    game.day,
          year:   textYear,
          hour:   game.hour,
          minute: game.minute,
        );
      }
      weeks[w][s] = game;
    }
  }

  final dropped = collected.length - gi;
  if (dropped > 0) {
    errors.add(
        'Warning: $dropped game(s) exceeded the 17-week capacity ($capacity) and were dropped.');
  }
  if (gi < capacity) {
    errors.add(
        'Warning: only $gi game(s) found; expected $capacity for a full season.');
  }

  return ScheduleParseResult(weeks, errors);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Resolves a team name string to a kTeamNames index.
/// Case-insensitive; tries exact match first, then prefix.
/// Returns null and adds an error if unresolvable.
int? _resolveTeam(String name, List<String> errors) {
  final q = name.toLowerCase();
  for (int i = 0; i < 32; i++) {
    if (kTeamNames[i].toLowerCase() == q) return i;
  }
  for (int i = 0; i < 32; i++) {
    if (kTeamNames[i].toLowerCase().contains(q)) return i;
  }
  errors.add('Unknown team: "$name"');
  return null;
}
