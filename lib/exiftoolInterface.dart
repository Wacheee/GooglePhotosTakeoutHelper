// ignore_for_file: file_names

import 'dart:convert';
import 'dart:io';
import 'utils.dart';

ExiftoolInterface? exiftool;

Future<bool> initExiftool() async {
  exiftool = await ExiftoolInterface.find();
  if (exiftool != null) {
    exifToolInstalled = true;
    return true;
  } else {
    return false;
  }
}

/// Cross-platform interface for exiftool (read/write EXIF data)
class ExiftoolInterface {
  ExiftoolInterface._(this.exiftoolPath);
  final String exiftoolPath;

  /// Attempts to find exiftool in PATH and returns an instance, or null if not found
  static Future<ExiftoolInterface?> find() async {
    final String exe = Platform.isWindows ? 'exiftool.exe' : 'exiftool';
    final String? path = await _which(exe);
    if (path != null) {
      return ExiftoolInterface._(path);
    }
    // Not found in PATH, check same directory as running binary
    String? binDir;
    // Try to get the directory of the running executable (cross-platform)
    try {
      // Platform.resolvedExecutable gives the full path to the Dart/Flutter binary
      binDir = File(Platform.resolvedExecutable).parent.path;
    } catch (_) {
      // If any error occurs (should be rare), set binDir to null
      binDir = null;
    }
    if (binDir != null) {
      // Construct the path to exiftool in the same directory as the binary
      final exiftoolFile = File('$binDir${Platform.pathSeparator}$exe');
      // Check if exiftool exists at this location
      if (await exiftoolFile.exists()) {
        // If found, return an instance using this path
        return ExiftoolInterface._(exiftoolFile.path);
      }
      // Also check for binary in ./exif_tool/ subfolder to satisfy requirement of https://github.com/jaimetur/PhotoMigrator
      final exiftoolSubdirFile = File(
        '$binDir${Platform.pathSeparator}exif_tool${Platform.pathSeparator}$exe',
      );
      if (await exiftoolSubdirFile.exists()) {
        return ExiftoolInterface._(exiftoolSubdirFile.path);
      }
    }
    // If not found, return null
    return null;
  }

  /// Reads all EXIF data from [file] and returns as a Map
  Future<Map<String, dynamic>> readExif(final File file) async {
    final result = await Process.run(exiftoolPath, ['-j', '-n', file.path]);
    if (result.exitCode != 0) {
      log(
        'exiftool returned a non 0 code for reading ${file.path} with error: ${result.stderr}',
        level: 'error',
      );
    }
    try {
      final List<dynamic> jsonList = jsonDecode(result.stdout);
      if (jsonList.isEmpty) return {};
      final map = Map<String, dynamic>.from(jsonList.first);
      map.remove('SourceFile');
      return map;
    } on FormatException catch (_) {
      // this is when json is bad
      return {};
    } on FileSystemException catch (_) {
      // this happens for issue #143
      // "Failed to decode data using encoding 'utf-8'"
      // maybe this will self-fix when dart itself support more encodings
      return {};
    } on NoSuchMethodError catch (_) {
      // this is when tags like photoTakenTime aren't there
      return {};
    }
  }

  /// Reads only the specified EXIF tags from [file] and returns as a Map
  Future<Map<String, dynamic>> readExifBatch(
    final File file,
    final List<String> tags,
  ) async {
    if (tags.isEmpty) {
      return <String, dynamic>{};
    }
    final args = <String>['-j', '-n'];
    args.addAll(tags.map((final tag) => '-$tag'));
    args.add(file.path);
    final result = await Process.run(exiftoolPath, args);
    if (result.exitCode != 0) {
      log(
        'exiftool returned a non 0 code for reading ${file.path} with error: ${result.stderr}',
        level: 'error',
      );
    }
    try {
      final List<dynamic> jsonList = jsonDecode(result.stdout);
      if (jsonList.isEmpty) return {};
      final map = Map<String, dynamic>.from(jsonList.first);
      map.remove('SourceFile');
      return map;
    } on FormatException catch (_) {
      // this is when json is bad
      return {};
    } on FileSystemException catch (_) {
      // this happens for issue #143
      // "Failed to decode data using encoding 'utf-8'"
      // maybe this will self-fix when dart itself support more encodings
      return {};
    } on NoSuchMethodError catch (_) {
      // this is when tags like photoTakenTime aren't there
      return {};
    }
  }

  /// Writes multiple EXIF tags to [file]. [tags] is a map of tag name to value.
  Future<bool> writeExifBatch(
    final File file,
    final Map<String, String> tags,
  ) async {
    final args = <String>['-overwrite_original'];
    tags.forEach((final tag, final value) => args.add('-$tag=$value'));
    args.add(file.path);
    final result = await Process.run(exiftoolPath, args);
    if (result.exitCode == 0) {
      return true;
    } else {
      if (isVerbose) {
        log(
          '[Step 5/8] Writing exif to file ${file.path} failed. ${result.stderr}',
          level: 'error',
        );
      } else {
        print(
          '\n[ERROR] [Step 5/8] Writing exif to file ${file.path} failed. ${result.stderr}',
        );
      }
      return false;
    }
  }
}

/// Helper to find an executable in PATH (like 'which' or 'where')
Future<String?> _which(final String bin) async {
  final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
    bin,
  ]);
  if (result.exitCode != 0) return null;
  final output = result.stdout.toString();
  final lines = output
      .split(RegExp(r'[\r\n]+'))
      .where((final l) => l.trim().isNotEmpty)
      .toList();
  return lines.isEmpty ? null : lines.first.trim();
}
