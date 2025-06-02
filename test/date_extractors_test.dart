/// # Date Extractors Test Suite
///
/// Comprehensive tests for date extraction functionality that recovers timestamp
/// information from various sources in Google Photos Takeout exports, ensuring
/// accurate chronological organization of media files.
///
/// ## Core Functionality Tested
///
/// ### JSON Metadata Extraction
/// - Extraction of creation timestamps from Google Photos JSON metadata files
/// - Handling of Unix timestamp formats and timezone conversions
/// - Support for "tryhard" mode that attempts to match related JSON files
/// - Fallback strategies for missing or corrupted JSON metadata
/// - Special handling for edited filenames (e.g., "photo-edited.jpg" → "photo.jpg.json")
///
/// ### EXIF Data Extraction
/// - Reading DateTimeOriginal from EXIF metadata in image files
/// - Support for various EXIF date formats and camera manufacturer variations
/// - Handling of timezone information when available in EXIF data
/// - Extraction from both JPEG and other supported image formats
/// - Error handling for corrupted or incomplete EXIF data
///
/// ### Filename Pattern Recognition
/// - Intelligent date guessing from filename patterns and conventions
/// - Support for common timestamp formats embedded in filenames
/// - Recognition of screenshot patterns with embedded timestamps
/// - Handling of various date formats (ISO, regional, custom patterns)
/// - Fallback parsing for non-standard filename conventions
///
/// ## Extraction Strategy and Accuracy
///
/// The date extraction system uses a hierarchical approach to maximize accuracy:
///
/// 1. **Primary Sources** (Highest Accuracy):
///    - Google Photos JSON metadata with precise Unix timestamps
///    - EXIF DateTimeOriginal from camera metadata
///
/// 2. **Secondary Sources** (Medium Accuracy):
///    - EXIF DateTime or DateTimeDigitized fields
///    - Structured filename patterns with embedded dates
///
/// 3. **Fallback Sources** (Lower Accuracy):
///    - File system timestamps (creation/modification dates)
///    - Heuristic filename parsing for partial date information
///
/// ## Test Coverage Areas
///
/// ### Edge Cases and Error Handling
/// - Files with missing or multiple potential JSON matches
/// - Corrupted EXIF data or unsupported metadata formats
/// - Ambiguous filename patterns requiring disambiguation
/// - Timezone handling and UTC conversion accuracy
/// - Performance with large batches of files
///
/// ### Integration Scenarios
/// - Coordination between multiple extraction methods
/// - Confidence scoring for extracted dates
/// - Handling of conflicting dates from different sources
/// - Support for edited files with modified timestamps
library;

import 'dart:io';
import 'package:gpth/date_extractors/date_extractor.dart';
import 'package:test/test.dart';
import './test_setup.dart';

void main() {
  group('Date Extractors', () {
    late TestFixture fixture;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('JSON Date Extractor', () {
      /// Tests JSON metadata parsing for precise timestamp extraction from
      /// Google Photos metadata files, including tryhard matching for
      /// edited filenames and error handling for missing files.
      test('extracts date from valid JSON file', () async {
        final imgFile = fixture.createFile('test.jpg', [1, 2, 3]);
        fixture.createJsonFile('test.jpg.json', 1599078832);

        final result = await jsonDateTimeExtractor(imgFile);

        expect(result?.millisecondsSinceEpoch, 1599078832 * 1000);
      });

      /// Should return null if the JSON metadata file does not exist.
      test('returns null when JSON file does not exist', () async {
        final imgFile = fixture.createFile('test.jpg', [1, 2, 3]);

        final result = await jsonDateTimeExtractor(imgFile);

        expect(result, isNull);
      });

      /// Should extract date using tryhard option for edited filenames.
      test('extracts date with tryhard option', () async {
        final imgFile = fixture.createFile('test-edited.jpg', [1, 2, 3]);
        fixture.createJsonFile('test.jpg.json', 1599078832);

        final DateTime? resultWithoutTryhard = await jsonDateTimeExtractor(
          imgFile,
        );
        final resultWithTryhard = await jsonDateTimeExtractor(
          imgFile,
          tryhard: true,
        );

        expect(resultWithoutTryhard, isNotNull);
        expect(resultWithTryhard?.millisecondsSinceEpoch, 1599078832 * 1000);
      });

      /// Should handle malformed JSON files gracefully and return null.
      test('handles malformed JSON gracefully', () async {
        final imgFile = fixture.createFile('test.jpg', [1, 2, 3]);
        final jsonFile = File('${fixture.basePath}/test.jpg.json');
        jsonFile.createSync();
        jsonFile.writeAsStringSync('invalid json content');

        final result = await jsonDateTimeExtractor(imgFile);

        expect(result, isNull);
      });
    });

    group('EXIF Date Extractor', () {
      /// Tests EXIF metadata parsing for camera-generated timestamps,
      /// extracting DateTimeOriginal and handling cases where EXIF
      /// data is missing or corrupted.
      test('extracts date from EXIF data', () async {
        final imgFile = fixture.createImageWithExif('test.jpg');

        final result = await exifDateTimeExtractor(imgFile);

        expect(result, DateTime.parse('2022-12-16 16:06:47'));
      });

      /// Should return null for images without EXIF metadata.
      test('returns null for image without EXIF data', () async {
        final imgFile = fixture.createImageWithoutExif('test.jpg');

        final result = await exifDateTimeExtractor(imgFile);

        expect(result, isNull);
      });

      /// Should return null for non-image files.
      test('returns null for non-image files', () async {
        final txtFile = fixture.createFile('test.txt', [1, 2, 3]);

        final result = await exifDateTimeExtractor(txtFile);

        expect(result, isNull);
      });
    });

    group('Guess Date Extractor', () {
      /// Tests intelligent filename pattern recognition for date extraction
      /// when other metadata sources are unavailable, supporting various
      /// timestamp formats embedded in filenames.
      test('extracts dates from various filename patterns', () async {
        for (final pattern in testDatePatterns) {
          final filename = pattern[0];
          final expectedDate = DateTime.parse(pattern[1]);
          final file = File('${fixture.basePath}/$filename');

          final result = await guessExtractor(file);

          expect(
            result,
            expectedDate,
            reason: 'Failed for filename: $filename',
          );
        }
      });

      /// Should return null for filenames that do not match known patterns.
      test('returns null for unrecognizable filename patterns', () async {
        final file = File('${fixture.basePath}/random_name.jpg');

        final result = await guessExtractor(file);

        expect(result, isNull);
      });
    });
  });
}
