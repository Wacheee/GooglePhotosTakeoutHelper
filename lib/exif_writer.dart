import 'dart:io';
import 'dart:typed_data';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:exif_reader/exif_reader.dart';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'date_extractors/date_extractor.dart';
import 'utils.dart';

//Check if it is a supported file format by the Image library to write to EXIF.
//Currently supported formats are: JPG, PNG/Animated APNG, GIF/Animated GIF, BMP, TIFF, TGA, PVR, ICO (as of Image 4.5.4)
bool isSupportedToWriteToExif(final File file) {
  final String extension = p.extension(file.path).toLowerCase();

  switch (extension) {
    case '.jpg':
      return true;
    case '.jpeg':
      return true;
    case '.png':
      return true;
    case '.gif':
      return true;
    case '.bmp':
      return true;
    case '.tiff':
      return true;
    case '.tga':
      return true;
    case '.pvr':
      return true;
    case '.ico':
      return true;
    default:
      return false;
  }
}

Future<bool> writeDateTimeToExif(
  final DateTime dateTime,
  final File file,
) async {
  //Check if the file format supports writing to exif
  if (isSupportedToWriteToExif(file)) {
    //Check if the file already has EXIF exif data. If function returns a DateTime, skip.
    if (await exifDateTimeExtractor(file) == null) {
      Image? image;
      try {
        image = decodeNamedImage(
          file.path,
          file.readAsBytesSync(),
        ); //Decode the image
      } catch (e) {
        log('[Step 5/8] Found DateTime in json, but missing in EXIF for file: ${file.path}. Failed to write because of error during decoding: $e',level: 'error');
        return false; // Ignoring errors during image decoding as it may not be a valid image file
      }
      if (image != null && image.hasExif) {
        final DateFormat exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
        image.exif.imageIfd['DateTime'] = exifFormat.format(dateTime);
        image.exif.exifIfd['DateTimeOriginal'] = exifFormat.format(dateTime);
        image.exif.exifIfd['DateTimeDigitized'] = exifFormat.format(dateTime);
        final Uint8List? newbytes = encodeNamedImage(
          file.path,
          image,
        ); //This overwrites the original file with the new Exif data.
        if (newbytes != null) {
          file.writeAsBytesSync(newbytes);
          log('[Step 5/8] New DateTime written ${dateTime.toString()} to EXIF: ${file.path}');
          return true;
        } else {
          log('[Step 5/8] Found DateTime in json, but missing in EXIF for file: ${file.path}. Failed to write because encoding returned null', level: 'error');
          return false; // Failed to encode image while writing DateTime.
        }
      }
    }
  }
  return false;
}

Future<bool> writeGpsToExif(
  final DMSCoordinates coordinates,
  final File file,
) async {
  //Check if the file format supports writing to exif
  if (isSupportedToWriteToExif(file)) {
    //Check if the file already has EXIF data and if yes, skip.
    final bool filehasExifCoordinates = await checkIfFileHasExifCoordinates(
      file,
    );
    if (!filehasExifCoordinates) {
      log(
        '[Step 5/8] Found coordinates in json, but missing in EXIF for file: ${file.path}',
      );
      // This is an edgecase where the json file has coordinates but the image file doesn't have EXIF data.
      Image? image;
      try {
        image = decodeNamedImage(
          file.path,
          file.readAsBytesSync(),
        ); //FIXME image decoding doesn't work for png files but only for jpg and jpeg.
      } catch (e) {
        log('[Step 5/8] Could not decode: ${file.path}. Failed with error: $e', level: 'error');
        return false; // Ignoring errors during image decoding. Currently happens for png files.
      }
      if (image != null && image.hasExif) {
        image.exif.gpsIfd.gpsLatitude = coordinates.latSeconds;
        image.exif.gpsIfd.gpsLongitude = coordinates.longSeconds;
        image.exif.gpsIfd.gpsLatitudeRef =
            coordinates.latDirection.abbreviation;
        image.exif.gpsIfd.gpsLongitudeRef =
            coordinates.longDirection.abbreviation;
        final Uint8List? newbytes = encodeNamedImage(
          file.path,
          image,
        ); //This overwrites the original file with the new Exif data.
        if (newbytes != null) {
          file.writeAsBytesSync(newbytes);
          log('[Step 5/8] New coordinates written to EXIF: ${file.path}');
          return true;
        } else {
          return false;
        }
      }
    }
  }
  return false;
}

//Check if the file already has EXIF data and if yes, skip.
Future<bool> checkIfFileHasExifCoordinates(final File file) async {
  // NOTE: reading whole file may seem slower than using readExifFromFile
  // but while testing it was actually 2x faster on my pc 0_o
  // i have nvme + btrfs, but still, will leave as is
  final Uint8List bytes = await file.readAsBytes();
  // this returns empty {} if file doesn't have exif so don't worry
  final Map<String, IfdTag> tags = await readExifFromBytes(bytes);

  if (tags['GPS GPSLatitude'] != null && tags['GPS GPSLongitude'] != null) {
    return true;
  }
  return false;
}
