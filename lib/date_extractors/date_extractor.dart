import 'dart:io';

export 'exif_extractor.dart';
export 'guess_extractor.dart';
export 'json_extractor.dart';

/// Function that can take a file and potentially extract DateTime of it
typedef DateTimeExtractor = Future<DateTime?> Function(File);
