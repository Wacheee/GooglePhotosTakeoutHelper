// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:math' as math;
import 'package:exif_reader/exif_reader.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import '../exiftoolInterface.dart';
import '../utils.dart';

/// DateTime from exif data *potentially* hidden within a [file]
///
/// You can try this with *any* file, it either works or not 🤷
/// It will either use exiftool if available or the exif_read library
Future<DateTime?> exifDateTimeExtractor(final File file) async {
  //If file is >maxFileSize - return null. https://github.com/brendan-duncan/image/issues/457#issue-1549020643
  if (await file.length() > maxFileSize && enforceMaxFileSize) {
    log(
      '[Step 4/8] The file is larger than the maximum supported file size of ${maxFileSize.toString()} bytes. File: ${file.path}',
      level: 'error',
    );
    return null;
  }

  //Getting mimeType.
  String? mimeType = lookupMimeType(file.path);
  if (mimeType == null) {
    //lookupMimeType sometimes returns null. Using fallbacks in those cases.
    if (exifToolInstalled) {
      mimeType = (await exiftool!.readExifBatch(file, [
        'MIMEType',
      ])).entries.first.value.toString().toLowerCase();
      log(
        'Got MimeType $mimeType of ${file.path} from exifTool because it was null initially.',
      );
    } else {
      //We do some unreliable checks by file extension, write mimeType manually and hope for the best.
      switch (extension(file.path)) {
        case '.jpg':
        case '.jpeg':
          mimeType = 'image/jpeg';
          break;
        case '.png':
          mimeType = 'image/png';
          break;
        case '.tiff':
        case '.tif':
          mimeType = 'image/tiff';
          break;
        case '.heic':
        case '.heif':
          mimeType = 'image/heic';
          break;
        case '.webp':
          mimeType = 'image/webp';
          break;
        case '.jxl':
          mimeType = 'image/jxl';
          break;
        case '.arw':
          mimeType = 'image/x-sony-arw';
          break;
        case '.raw':
          mimeType = 'image/x-panasonic-raw';
          break;
        case '.dng':
          mimeType = 'image/x-adobe-dng';
          break;
        case '.crw':
          mimeType = 'image/x-canon-crw';
          break;
        case '.cr3':
          mimeType = 'image/x-canon-cr3';
          break;
        case '.nrw':
          mimeType = 'image/x-nikon-nrw';
          break;
        case '.nef':
          mimeType = 'image/x-nikon-nef';
          break;
        case '.raf':
          mimeType = 'image/x-fuji-raf';
          break;
        default:
          mimeType = null;
      }
    }
  }

  // We use the native way for jpeg because we know they can be handled. For speed and performance.
  //Only for everything else we don't know we use exiftools and if it is not available we try with the native way, because hey, maybe we are lucky.
  if (exifToolInstalled && mimeType != null && mimeType == 'image/jpeg') {
    final DateTime? result = await _nativeExif_readerExtractor(file);
    if (result != null) {
      return result;
    } else {
      return _exifToolExtractor(
        file,
      ); //Fallback because sometimes mimetype is image/jpeg based on extension but content is png and then native way fails.
    }
  }
  // Use exiftool if available and file is an image or video
  else if (exifToolInstalled &&
      mimeType != null &&
      (mimeType.startsWith('image/') ||
          mimeType.startsWith('video/') ||
          mimeType == 'model/vnd.mts')) {
    return _exifToolExtractor(file);
    // Use dart library exif_reader limited to images if exiftool is not available
  } else if (!exifToolInstalled &&
      mimeType != null &&
      mimeType.startsWith('image/')) {
    return _nativeExif_readerExtractor(file);
  }
  //This logic below is only to give a tailored error message because if you get here, something is wrong.
  if (exifToolInstalled) {
    log(
      "$mimeType is a weird mime type! Please create an issue if you get this error message, as we currently can't handle it.",
      level: 'error',
    );
  } else {
    log(
      '$mimeType skipped. Reading from this file format is only supported with exiftool',
      level: 'warning',
    );
  }
  return null; //If unsupported
}

///Extracts DateTime from File through ExifTool library
Future<DateTime?> _exifToolExtractor(final File file) async {
  try {
    final tags = await exiftool!.readExifBatch(file, [
      'DateTimeOriginal',
      'MediaCreateDate',
      'CreationDate',
      'TrackCreateDate',
      'CreateDate',
      'DateTimeDigitized',
      'GPSDateStamp',
      'DateTime',
    ]);
    //The order is in order of reliability and important
    String? datetime =
        tags['DateTimeOriginal'] ?? //EXIF
        tags['MediaCreateDate'] ?? //QuickTime/XMP
        tags['CreationDate'] ?? //XMP
        tags['TrackCreateDate']; //?? //QuickTime
    //tags['CreateDate'] ?? // can be overwritten by editing software
    //tags['DateTimeDigitized'] ?? //may reflect scanning or import time
    //tags['DateTime']; //generic and editable
    if (datetime == null) {
      log(
        "Exiftool was not able to extract an acceptable DateTime for ${file.path}. Those Tags are accepted: 'DateTimeOriginal', 'MediaCreateDate', 'CreationDate','TrackCreateDate','. The file has those Tags: ${tags.toString()}",
        level: 'warning',
      );
      return null;
    }
    // Normalize separators and parse
    datetime = datetime
        .replaceAll('-', ':')
        .replaceAll('/', ':')
        .replaceAll('.', ':')
        .replaceAll('\\', ':')
        .replaceAll(': ', ':0')
        .substring(0, math.min(datetime.length, 19))
        .replaceFirst(':', '-')
        .replaceFirst(':', '-');

    final DateTime? parsedDateTime = DateTime.tryParse(datetime);

    if (parsedDateTime == DateTime.parse('2036-01-01T23:59:59.000000Z')) {
      //we keep this for safety for this edge case: https://ffmpeg.org/pipermail/ffmpeg-user/2023-April/056265.html
      log(
        '[Step 4/8] Extracted DateTime before January 1st 1970 from EXIF for ${file.path}. Therefore the DateTime from other extractors is not being changed.',
        level: 'warning',
      );
      return null;
    } else {
      log(
        '[Step 4/8] Sucessfully extracted DateTime from EXIF through Exiftool for ${file.path}',
      );
      return parsedDateTime;
    }
  } catch (e) {
    log('[Step 4/8] exiftool read failed: ${e.toString()}', level: 'error');
    return null;
  }
}

///Extracts DateTime from File through Exif_reader library
Future<DateTime?> _nativeExif_readerExtractor(final File file) async {
  final bytes = await file.readAsBytes();
  // this returns empty {} if file doesn't have exif so don't worry
  final tags = await readExifFromBytes(bytes);
  String? datetime;
  // try if any of these exists
  datetime ??= tags['Image DateTime']?.printable;
  datetime ??= tags['EXIF DateTimeOriginal']?.printable;
  datetime ??= tags['EXIF DateTimeDigitized']?.printable;
  if (datetime == null) return null;
  // Normalize separators and parse
  datetime = datetime
      .replaceAll('-', ':')
      .replaceAll('/', ':')
      .replaceAll('.', ':')
      .replaceAll('\\', ':')
      .replaceAll(': ', ':0')
      .substring(0, math.min(datetime.length, 19))
      .replaceFirst(':', '-')
      .replaceFirst(':', '-');

  final DateTime? parsedDateTime = DateTime.tryParse(datetime);

  if (parsedDateTime == DateTime.parse('2036-01-01T23:59:59.000000Z')) {
    //we keep this for safety for this edge case: https://ffmpeg.org/pipermail/ffmpeg-user/2023-April/056265.html
    log(
      '[Step 4/8] Extracted DateTime before January 1st 1970 from EXIF for ${file.path}. Therefore the DateTime from other extractors is not being changed.',
      level: 'warning',
    );
    return null;
  } else {
    log(
      '[Step 4/8] Sucessfully extracted DateTime from EXIF through native library for ${file.path}',
    );
    return parsedDateTime;
  }
}
