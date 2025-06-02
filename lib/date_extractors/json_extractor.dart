import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import '../extras.dart' as extras;
import '../utils.dart';

/// Finds corresponding json file with info from media file and gets 'photoTakenTime' from it
Future<DateTime?> jsonDateTimeExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await _jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return null;
  try {
    final dynamic data = jsonDecode(await jsonFile.readAsString());
    final int epoch = int.parse(data['photoTakenTime']['timestamp'].toString());
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  } on FormatException catch (_) {
    // this is when json is bad
    return null;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return null;
  } on NoSuchMethodError catch (_) {
    // this is when tags like photoTakenTime aren't there
    return null;
  }
}

/// Attempts to find the corresponding JSON file for a media file
///
/// Tries multiple strategies to locate JSON files, including handling
/// filename truncation, bracket swapping, and extra format removal.
///
/// [file] Media file to find JSON for
/// [tryhard] If true, uses more aggressive matching strategies
/// Returns the JSON file if found, null otherwise
Future<File?> _jsonForFile(
  final File file, {
  required final bool tryhard,
}) async {
  final Directory dir = Directory(p.dirname(file.path));
  final String name = p.basename(file.path);
  // will try all methods to strip name to find json
  for (final String Function(String s) method in <String Function(String s)>[
    // none
    (final String s) => s,
    _shortenName,
    // test: combining this with _shortenName?? which way around?
    _bracketSwap,
    _removeExtra,
    _noExtension,
    // use those two only with tryhard
    // look at https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/175
    // thanks @denouche for reporting this!
    if (tryhard) ...<String Function(String filename)>[
      _removeExtraRegex,
      _removeDigit, // most files with '(digit)' have jsons, so it's last
    ],
  ]) {
    final File jsonFile = File(p.join(dir.path, '${method(name)}.json'));
    if (await jsonFile.exists()) return jsonFile;
  }
  return null;
}

/// Removes file extension from filename
///
/// Handles cases where original file had no extension but Google added one.
///
/// [filename] Original filename
/// Returns filename without extension
String _noExtension(final String filename) =>
    p.basenameWithoutExtension(File(filename).path);

/// Removes digit patterns like "(1)" from filenames
///
/// [filename] Original filename
/// Returns filename with digit patterns removed
String _removeDigit(final String filename) =>
    filename.replaceAll(RegExp(r'\(\d\)\.'), '.');

/// Removes "extra" format suffixes safely using predefined list
///
/// Only removes suffixes from the known safe list in extraFormats.
/// Handles Unicode normalization for cross-platform compatibility.
///
/// [filename] Original filename
/// Returns filename with extra formats removed
String _removeExtra(final String filename) {
  // MacOS uses NFD that doesn't work with our accents 🙃🙃
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
  final String normalizedFilename = unorm.nfc(filename);
  for (final String extra in extras.extraFormats) {
    if (normalizedFilename.contains(extra)) {
      return normalizedFilename.replaceLast(extra, '');
    }
  }
  return normalizedFilename;
}

/// Removes extra format suffixes using regex patterns
///
/// More aggressive than _removeExtra, uses regex to match
/// pattern like "something-edited(1).jpg" -> "something.jpg"
///
/// [filename] Original filename
/// Returns filename with extra patterns removed
String _removeExtraRegex(final String filename) {
  // MacOS uses NFD that doesn't work with our accents 🙃🙃
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
  final String normalizedFilename = unorm.nfc(filename);
  // include all characters, also with accents
  final Iterable<RegExpMatch> matches = RegExp(
    r'(?<extra>-[A-Za-zÀ-ÖØ-öø-ÿ]+(\(\d\))?)\.\w+$',
  ).allMatches(normalizedFilename);
  if (matches.length == 1) {
    return normalizedFilename.replaceAll(
      matches.first.namedGroup('extra')!,
      '',
    );
  }
  return normalizedFilename;
}

// this resolves years of bugs and head-scratches 😆
// f.e: https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/8#issuecomment-736539592
String _shortenName(final String filename) => '$filename.json'.length > 51
    ? filename.substring(0, 51 - '.json'.length)
    : filename;

// thanks @casualsailo and @denouche for bringing attention!
// https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/188
// and https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/175
/// Handles bracket number swapping in filenames
///
/// Some files have patterns like "image(11).jpg" with JSON "image.jpg(11).json"
/// This function swaps the bracket position to match.
///
/// [filename] Original filename
/// Returns filename with brackets repositioned
String _bracketSwap(final String filename) {
  // this is with the dot - more probable that it's just before the extension
  final RegExpMatch? match = RegExp(
    r'\(\d+\)\.',
  ).allMatches(filename).lastOrNull;
  if (match == null) return filename;
  final String bracket = match.group(0)!.replaceAll('.', ''); // remove dot
  // remove only last to avoid errors with filenames like:
  // 'image(3).(2)(3).jpg' <- "(3)." repeats twice
  final String withoutBracket = filename.replaceLast(bracket, '');
  return '$withoutBracket$bracket';
}

/// This is to get coordinates from the json file. Expects media file and finds json.
Future<DMSCoordinates?> jsonCoordinatesExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await _jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return null;
  try {
    final Map<String, dynamic> data = jsonDecode(await jsonFile.readAsString());
    final double lat = data['geoData']['latitude'] as double;
    final double long = data['geoData']['longitude'] as double;
    //var alt = double.tryParse(data['geoData']['altitude']); //Info: Altitude is not used.
    if (lat == 0.0 || long == 0.0) {
      return null;
    } else {
      final DDCoordinates ddcoords = DDCoordinates(
        latitude: lat,
        longitude: long,
      );
      final DMSCoordinates dmscoords = DMSCoordinates.fromDD(ddcoords);
      return dmscoords;
    }
  } on FormatException catch (_) {
    // this is when json is bad
    return null;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return null;
  } on NoSuchMethodError catch (_) {
    // this is when tags like photoTakenTime aren't there
    return null;
  }
}
