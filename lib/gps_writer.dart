import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart';

import 'date_extractors/json_extractor.dart';

/// Writes GPS coordinates from the sidecar JSON into the image's EXIF data.
/// If the JSON file doesn't contain GPS information, nothing is changed.
Future<void> writeGpsFromJson(File image, {bool tryHard = false}) async {
  final jsonFile = await jsonFileFor(image, tryhard: tryHard);
  if (jsonFile == null) return;

  Map<String, dynamic> data;
  try {
    data = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final gps = (data['geoDataExif'] ?? data['geoData'] ?? data['location']) as Map?;
  if (gps == null) return;
  final lat = _toDouble(gps['latitude']);
  final lon = _toDouble(gps['longitude']);
  if (lat == null || lon == null) return;

  final bytes = await image.readAsBytes();
  final img = decodeImage(bytes);
  if (img == null) return;

  img.exif ??= ExifData();
  img.exif!.tags['GPSLatitude'] = _decimalToDms(lat);
  img.exif!.tags['GPSLatitudeRef'] = lat >= 0 ? 'N' : 'S';
  img.exif!.tags['GPSLongitude'] = _decimalToDms(lon);
  img.exif!.tags['GPSLongitudeRef'] = lon >= 0 ? 'E' : 'W';

  final encoded = encodeJpg(img, exif: img.exif);
  await image.writeAsBytes(encoded);
}

/// Convert decimal coordinate to [Rational] list used by EXIF.
List<Rational> _decimalToDms(double value) {
  final deg = value.abs().floor();
  final minFloat = (value.abs() - deg) * 60;
  final min = minFloat.floor();
  final sec = ((minFloat - min) * 60);
  return [
    Rational(deg, 1),
    Rational(min, 1),
    Rational((sec * 1000).round(), 1000),
  ];
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  return double.tryParse(v.toString());
}
