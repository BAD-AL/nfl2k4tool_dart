import 'dart:io';
import 'package:nfl2k4tool_dart/nfl2k4tool_dart.dart';

NFL2K4Gamesave loadFile(String path) =>
    NFL2K4Gamesave.fromBytes(File(path).readAsBytesSync());

void saveFile(NFL2K4Gamesave save, String path) {
  final isZipOut = path.toLowerCase().endsWith('.zip');
  if (isZipOut || (save.isZip && !path.toLowerCase().endsWith('.dat'))) {
    File(path).writeAsBytesSync(save.toZipBytes());
  } else {
    File(path).writeAsBytesSync(save.toBytes());
  }
}
