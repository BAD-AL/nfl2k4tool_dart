import 'constants.dart';

/// An ordered list of player field names that controls which attributes are
/// read (or written) for each player, and in what column order.
///
/// Used by both the CLI (`-key=...`) and the web library so that callers
/// can request exactly the fields they care about.
///
/// Field names are matched case-insensitively by [PlayerRecord.getAttribute].
/// Any name accepted by that method is valid here.
class RosterKey {
  final List<String> fields;

  const RosterKey(this.fields);

  /// Parse a comma-separated key string, e.g. `"Position,JerseyNumber,fname,lname"`.
  /// Trims whitespace; ignores empty segments.
  /// Throws [ArgumentError] if the result is empty or contains an unrecognised field.
  factory RosterKey.parse(String keyString) {
    final fields = keyString
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    if (fields.isEmpty) throw ArgumentError('Key must specify at least one field.');
    for (final f in fields) {
      if (!kAllFieldNames.contains(f.toLowerCase())) {
        throw ArgumentError(
            'Unknown field "$f". Valid fields: ${kAllFieldNames.join(', ')}');
      }
    }
    return RosterKey(fields);
  }

  /// Default key used when `-ab` is specified (abilities + scalars).
  static const RosterKey abilities = RosterKey([
    'Position', 'fname', 'lname', 'JerseyNumber',
    'Speed', 'Agility', 'Strength', 'Jumping', 'Coverage', 'PassRush',
    'RunCoverage', 'PassBlocking', 'RunBlocking', 'Catch', 'RunRoute',
    'BreakTackle', 'HoldOntoBall', 'PowerRunStyle', 'PassAccuracy',
    'PassArmStrength', 'PassReadCoverage', 'Tackle', 'KickPower', 'KickAccuracy',
    'Stamina', 'Durability', 'Leadership', 'Scramble', 'Composure',
    'Consistency', 'Aggressiveness',
    'College', 'DOB', 'PBP', 'Photo', 'YearsPro', 'Hand', 'Weight', 'Height',
  ]);

  /// Default key used when `-app` is specified (appearance).
  static const RosterKey appearance = RosterKey([
    'Position', 'fname', 'lname', 'JerseyNumber',
    'BodyType', 'Skin', 'Face', 'Dreads', 'Helmet', 'FaceMask', 'Visor',
    'EyeBlack', 'MouthPiece', 'LeftGlove', 'RightGlove',
    'LeftWrist', 'RightWrist', 'LeftElbow', 'RightElbow',
    'Sleeves', 'LeftShoe', 'RightShoe', 'NeckRoll', 'Turtleneck',
  ]);

  /// Combined abilities + appearance key.
  static final RosterKey all = RosterKey([
    ...abilities.fields,
    ...appearance.fields.skip(4), // skip the identity prefix duplicates
  ]);

  /// The active key for the current session.  Defaults to [all] and is updated
  /// by a `Key=` directive in [InputParser.applyText].  Persists across calls
  /// since a new [InputParser] is created for each apply operation.
  static RosterKey current = all;
}

/// Canonical lowercase set of all field names accepted by [PlayerRecord.getAttribute].
/// Ability names are derived directly from [kAbilityOffsets] to stay in sync.
/// Used for validation in [RosterKey.parse].
final Set<String> kAllFieldNames = {
  // Derived from kAbilityOffsets — single source of truth for ability names.
  ...kAbilityOffsets.keys.map((k) => k.toLowerCase()),
  // Identity / scalars
  'fname', 'lname', 'position', 'jerseynumber', 'pbp', 'photo',
  'yearspro', 'weight', 'height', 'dob', 'college', 'hand',
  // Appearance
  'bodytype', 'skin', 'face', 'dreads', 'helmet', 'facemask', 'visor',
  'eyeblack', 'mouthpiece', 'leftglove', 'rightglove',
  'leftwrist', 'rightwrist', 'leftelbow', 'rightelbow',
  'sleeves', 'leftshoe', 'rightshoe', 'neckroll', 'turtleneck',
};
