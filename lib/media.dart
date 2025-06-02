import 'dart:io';

import 'package:crypto/crypto.dart';
import 'utils.dart';

//Order is important!
///This is the extraction method through which a Media got its dateTime.
enum DateTimeExtractionMethod { json, exif, guess, jsonTryHard, none }

/// Abstract of a *media* - a photo or video
/// Main thing is the [file] - this should not change
///
/// [size] and [hash] getter are here because we can easily cache
///
/// [dateTakenAccuracy] is a number used to compare with other [Media]. When
/// you find a duplicate, use one that has lower [dateTakenAccuracy] number.
/// this and [dateTaken] should either both be null or both filled
class Media {
  Media(
    this.files, {
    this.dateTaken,
    this.dateTakenAccuracy,
    this.dateTimeExtractionMethod,
  });

  /// First file with media, used in early stage when albums are not merged
  ///
  /// BE AWARE OF HOW YOU USE IT
  File get firstFile => files.values.first;

  /// Map between albums and files of same given media
  ///
  /// This is heavily mutated - at first, media from year folders have this
  /// with single null key, and those from albums have one name.
  /// Then, they are merged into one by algos etc.
  ///
  /// At the end of the script, this will have *all* locations of given media,
  /// so that we can safely:
  /// ```dart
  /// // photo.runtimeType == Media;
  /// photo.files[null].move('output/one-big/');  // null is for year folders
  /// photo.files[<album_name>].move('output/albums/<album_name>/');
  /// ```
  Map<String?, File> files;

  // cache
  int? _size;

  /// will be used for finding duplicates/albums
  int get size => _size ??= firstFile.lengthSync();

  /// DateTaken from any source
  DateTime? dateTaken;

  /// higher the worse
  int? dateTakenAccuracy;

  /// The method/extractor that produced the DateTime ('json', 'exif', 'guess', 'jsonTryHard', 'none')
  DateTimeExtractionMethod? dateTimeExtractionMethod;

  //cache
  Digest? _hash;

  /// will be used for finding duplicates/albums
  /// WARNING: Returns same value for files > [defaultMaxFileSize]
  Digest get hash => _hash ??=
      ((firstFile.lengthSync() > defaultMaxFileSize) && enforceMaxFileSize)
      ? Digest(<int>[0])
      : sha256.convert(firstFile.readAsBytesSync());

  @override
  String toString() =>
      'Media('
      '$firstFile, '
      'dateTaken: $dateTaken'
      '${files.keys.length > 1 ? ', albums: ${files.keys}' : ''}'
      ')';
}
