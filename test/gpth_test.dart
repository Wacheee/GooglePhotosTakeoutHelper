import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:exif_reader/exif_reader.dart';
import 'package:gpth/date_extractors/date_extractor.dart';
import 'package:gpth/exif_writer.dart';
import 'package:gpth/extras.dart';
import 'package:gpth/folder_classify.dart';
import 'package:gpth/grouping.dart';
import 'package:gpth/media.dart';
import 'package:gpth/moving.dart';
import 'package:gpth/utils.dart';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  /// this is 1x1 green jg image, with exif:
  /// DateTime Original: 2022:12:16 16:06:47
  const String greenImgBase64 = '''
/9j/4AAQSkZJRgABAQAAAQABAAD/4QC4RXhpZgAATU0AKgAAAAgABQEaAAUAAAABAAAASgEbAAUA
AAABAAAAUgEoAAMAAAABAAEAAAITAAMAAAABAAEAAIdpAAQAAAABAAAAWgAAAAAAAAABAAAAAQAA
AAEAAAABAAWQAAAHAAAABDAyMzKQAwACAAAAFAAAAJyRAQAHAAAABAECAwCgAAAHAAAABDAxMDCg
AQADAAAAAf//AAAAAAAAMjAyMjoxMjoxNiAxNjowNjo0NwD/2wBDAAMCAgICAgMCAgIDAwMDBAYE
BAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQD
BAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ
EBD/wAARCAABAAEDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAA
AAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAI/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwD
AQACEQMRAD8AIcgXf//Z''';
  const String basepath = '/test/'; //Where the test files are created

  final Directory albumDir = Directory('${basepath}Vacation');
  final File imgFileGreen = File('${basepath}green.jpg');
  final File imgFile1 = File('${basepath}image-edited.jpg');
  final File jsonFile1 = File('${basepath}image-edited.jpg.json');
  // these names are from good old #8 issue...
  final File imgFile2 = File(
    '${basepath}Urlaub in Knaufspesch in der Schneifel (38).JPG',
  );
  final File jsonFile2 = File(
    '${basepath}Urlaub in Knaufspesch in der Schneifel (38).JP.json',
  );
  final File imgFile3 = File(
    '${basepath}Screenshot_2022-10-28-09-31-43-118_com.snapchat.jpg',
  );
  final File jsonFile3 = File(
    '${basepath}Screenshot_2022-10-28-09-31-43-118_com.snapcha.json',
  );
  final File imgFile4 = File('${basepath}simple_file_20200101-edited.jpg');
  final File imgFile4_1 = File('${basepath}simple_file_20200101-edited(1).jpg');
  final File jsonFile4 = File('${basepath}simple_file_20200101.jpg.json');
  final File imgFile5 = File(
    '${basepath}img_(87).(vacation stuff).lol(87).jpg',
  );
  final File jsonFile5 = File(
    '${basepath}img_(87).(vacation stuff).lol.jpg(87).json',
  );
  final File imgFile6 = File('${basepath}IMG-20150125-WA0003-modifié.jpg');
  final File imgFile6_1 = File('${basepath}IMG-20150125-WA0003-modifié(1).jpg');
  final File jsonFile6 = File('${basepath}IMG-20150125-WA0003.jpg.json');
  final List<Media> media = <Media>[
    Media(
      <String?, File>{null: imgFile1},
      dateTaken: DateTime(2020, 9),
      dateTakenAccuracy: 1,
    ),
    Media(
      <String?, File>{albumName(albumDir): imgFile1},
      dateTaken: DateTime(2022, 9),
      dateTakenAccuracy: 2,
    ),
    Media(
      <String?, File>{null: imgFile2},
      dateTaken: DateTime(2020),
      dateTakenAccuracy: 2,
    ),
    Media(
      <String?, File>{null: imgFile3},
      dateTaken: DateTime(2022, 10, 28),
      dateTakenAccuracy: 1,
    ),
    Media(<String?, File>{null: imgFile4}), // these two...
    // ...are duplicates
    Media(
      <String?, File>{null: imgFile4_1},
      dateTaken: DateTime(2019),
      dateTakenAccuracy: 3,
    ),
    Media(
      <String?, File>{null: imgFile5},
      dateTaken: DateTime(2020),
      dateTakenAccuracy: 1,
    ),
    Media(
      <String?, File>{null: imgFile6},
      dateTaken: DateTime(2015),
      dateTakenAccuracy: 1,
    ),
    Media(
      <String?, File>{null: imgFile6_1},
      dateTaken: DateTime(2015),
      dateTakenAccuracy: 1,
    ),
  ];

  /// Set up test stuff - create test shitty files in wherever pwd is
  /// We don't worry because we'll delete them later
  setUpAll(() {
    albumDir.createSync(recursive: true);
    imgFileGreen.createSync();
    imgFileGreen.writeAsBytesSync(
      base64.decode(greenImgBase64.replaceAll('\n', '')),
    );
    // apparently you don't need to .create() before writing 👍
    imgFile1.writeAsBytesSync(<int>[0, 1, 2]);
    imgFile1.copySync('${albumDir.path}/${basename(imgFile1.path)}');
    imgFile2.writeAsBytesSync(<int>[3, 4, 5]);
    imgFile3.writeAsBytesSync(<int>[6, 7, 8]);
    imgFile4.writeAsBytesSync(<int>[9, 10, 11]); // these two...
    imgFile4_1.writeAsBytesSync(<int>[9, 10, 11]); // ...are duplicates
    imgFile5.writeAsBytesSync(<int>[12, 13, 14]);
    imgFile6.writeAsBytesSync(<int>[15, 16, 17]);
    imgFile6_1.writeAsBytesSync(<int>[18, 19, 20]);
    void writeJson(final File file, final int time) {
      file.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode(<String, Object>{
          'title': 'test.jpg',
          'description': '',
          'imageViews': '1',
          'creationTime': <String, String>{
            'timestamp': '1702198242',
            'formatted': '10.12.2023, 08:50:42 UTC',
          },
          'photoTakenTime': <String, String>{
            'timestamp': '$time',
            'formatted': '01.05.2023, 14:32:37 UTC',
          },
          'geoData': <String, double>{
            'latitude': 41.3221611,
            'longitude': 19.8149139,
            'altitude': 143.09,
            'latitudeSpan': 0.0,
            'longitudeSpan': 0.0,
          },
          'geoDataExif': <String, double>{
            'latitude': 41.3221611,
            'longitude': 19.8149139,
            'altitude': 143.09,
            'latitudeSpan': 0.0,
            'longitudeSpan': 0.0,
          },
          'archived': true,
          'url': 'https://photos.google.com/photo/xyz',
          'googlePhotosOrigin': <String, Map<String, String>>{
            'mobileUpload': <String, String>{'deviceType': 'IOS_PHONE'},
          },
        }),
      );
    }

    writeJson(jsonFile1, 1599078832);
    writeJson(jsonFile2, 1683078832);
    writeJson(jsonFile3, 1666942303);
    writeJson(jsonFile4, 1683074444);
    writeJson(jsonFile5, 1680289442);
    writeJson(jsonFile6, 1422183600);
  });

  group('DateTime extractors', () {
    test('json', () async {
      expect(
        (await jsonDateTimeExtractor(imgFile1))?.millisecondsSinceEpoch,
        1599078832 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(imgFile2))?.millisecondsSinceEpoch,
        1683078832 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(imgFile3))?.millisecondsSinceEpoch,
        1666942303 * 1000,
      );
      // They *should* fail without tryhard
      // See b38efb5d / #175
      expect(
        (await jsonDateTimeExtractor(imgFile4))?.millisecondsSinceEpoch,
        1683074444 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(imgFile4_1))?.millisecondsSinceEpoch,
        null,
      );
      // Should work *with* tryhard
      expect(
        (await jsonDateTimeExtractor(
          imgFile4,
          tryhard: true,
        ))?.millisecondsSinceEpoch,
        1683074444 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(
          imgFile4_1,
          tryhard: true,
        ))?.millisecondsSinceEpoch,
        1683074444 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(imgFile5))?.millisecondsSinceEpoch,
        1680289442 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(imgFile6))?.millisecondsSinceEpoch,
        1422183600 * 1000,
      );
      expect(
        (await jsonDateTimeExtractor(imgFile6_1))?.millisecondsSinceEpoch,
        null,
      );
      expect(
        (await jsonDateTimeExtractor(
          imgFile6_1,
          tryhard: true,
        ))?.millisecondsSinceEpoch,
        1422183600 * 1000,
      );
    });
    test('exif', () async {
      expect(
        await exifDateTimeExtractor(imgFileGreen),
        DateTime.parse('2022-12-16 16:06:47'),
      );
    });
    test('guess', () async {
      final List<List<String>> files = <List<String>>[
        <String>[
          'Screenshot_20190919-053857_Camera-edited.jpg',
          '2019-09-19 05:38:57',
        ],
        <String>['MVIMG_20190215_193501.MP4', '2019-02-15 19:35:01'],
        <String>[
          'Screenshot_2019-04-16-11-19-37-232_com.jpg',
          '2019-04-16 11:19:37',
        ],
        <String>['signal-2020-10-26-163832.jpg', '2020-10-26 16:38:32'],
        <String>['VID_20220107_113306.mp4', '2022-01-07 11:33:06'],
        <String>[
          '00004XTR_00004_BURST20190216172030.jpg',
          '2019-02-16 17:20:30',
        ],
        <String>[
          '00055IMG_00055_BURST20190216172030_COVER.jpg',
          '2019-02-16 17:20:30',
        ],
        <String>['2016_01_30_11_49_15.mp4', '2016-01-30 11:49:15'],
        <String>['201801261147521000.jpg', '2018-01-26 11:47:52'],
        <String>['IMG_1_BURST20160623205107_COVER.jpg', '2016-06-23 20:51:07'],
        <String>['IMG_1_BURST20160520195318.jpg', '2016-05-20 19:53:18'],
        <String>['1990_06_16_07_30_00.jpg', '1990-06-16 07:30:00'],
        <String>['1869_12_30_16_59_57.jpg', '1869-12-30 16:59:57'],
      ];
      for (final List<String> f in files) {
        expect(await guessExtractor(File(f.first)), DateTime.parse(f.last));
      }
    });
  });
  test('Duplicate removal', () {
    expect(removeDuplicates(media, 40), 1);
    expect(media.length, 8);
    expect(
      media.firstWhereOrNull((final Media e) => e.firstFile == imgFile4),
      null,
    );
  });
  test('Extras removal', () {
    final List<Media> m = <Media>[
      Media(<String?, File>{null: imgFile1}),
      Media(<String?, File>{null: imgFile2}),
    ];
    expect(removeExtras(m), 1);
    expect(m.length, 1);
  });
  test('Album finding', () {
    // sadly, this will still modify [media] some, but won't delete anything
    final List<Media> copy = media.toList();
    removeDuplicates(copy, 40);

    final int countBefore = copy.length;
    findAlbums(copy);
    expect(countBefore - copy.length, 1);

    final Media albumed = copy.firstWhere(
      (final Media e) => e.files.length > 1,
    );
    expect(albumed.files.keys, <String?>[null, 'Vacation']);
    expect(albumed.dateTaken, media[0].dateTaken);
    expect(albumed.dateTaken == media[1].dateTaken, false); // be sure
    expect(copy.where((final Media e) => e.files.length > 1).length, 1);
    // fails because Dart is no Rust :/
    // expect(media.where((e) => e.albums != null).length, 1);
  });
  group('Utils', () {
    test('Stream.whereType()', () {
      final Stream<Object> stream = Stream<Object>.fromIterable(<Object>[
        1,
        'a',
        2,
        'b',
        3,
        'c',
      ]);
      expect(
        stream.whereType<int>(),
        emitsInOrder(<dynamic>[1, 2, 3, emitsDone]),
      );
    });
    test('Stream<FileSystemEntity>.wherePhotoVideo()', () {
      //    check if stream with random list of files is emitting only photos and videos
      //   use standard formats as jpg and mp4 but also rare ones like 3gp and eps
      final Stream<FileSystemEntity> stream =
          Stream<FileSystemEntity>.fromIterable(<FileSystemEntity>[
            File('a.jpg'),
            File('lol.json'),
            File('b.mp4'),
            File('c.3gp'),
            File('e.png'),
            File('f.txt'),
          ]);
      expect(
        // looked like File()'s couldn't compare correctly :/
        stream.wherePhotoVideo().map((final File event) => event.path),
        emitsInOrder(<dynamic>['a.jpg', 'b.mp4', 'c.3gp', 'e.png', emitsDone]),
      );
    });
    test('findNotExistingName()', () {
      expect(findNotExistingName(imgFileGreen).path, '${basepath}green(1).jpg');
      expect(
        findNotExistingName(File('${basepath}not-here.jpg')).path,
        '${basepath}not-here.jpg',
      );
    });
    test('getDiskFree()', () async {
      expect(await getDiskFree('.'), isNotNull);
    });
    test('Create win shortcut', () async {
      const shortcutPath = r'C:\Temp\MyShortcut.lnk';
      const targetPath = r'C:\Windows\System32\notepad.exe';

      // Ensure target exists
      if (!File(targetPath).existsSync()) {
        print('Target file does not exist: $targetPath');
        exit(1);
      }

      // Create folder if needed
      final shortcutDir = p.dirname(shortcutPath);
      if (!Directory(shortcutDir).existsSync()) {
        Directory(shortcutDir).createSync(recursive: true);
      }

      try {
        await createShortcutWin(shortcutPath, targetPath);
      } catch (e, stack) {
        print('❌ Failed to create shortcut:\n$e\n$stack');
      }
      // Verify that shortcut file now exists
      expect(File(shortcutPath).existsSync(), true);
      File(shortcutPath).deleteSync();
    });
  });
  group('folder_classify', () {
    List<Directory> tmpdirs;
    if (Platform.isWindows) {
      tmpdirs = <Directory>[
        Directory('./Photos from 2025'),
        Directory('./Photos from 1969'),
        Directory('./Photos from vacation'),
        Directory('C:/Windows/Temp/very-random-omg'),
      ];
    } else {
      tmpdirs = <Directory>[
        Directory('./Photos from 2025'),
        Directory('./Photos from 1969'),
        Directory('./Photos from vacation'),
        Directory('/tmp/very-random-omg'),
      ];
    }
    final List<Directory> dirs = tmpdirs;
    setUpAll(() async {
      for (Directory d in dirs) {
        await d.create();
      }
    });
    test('is year/album folder', () async {
      expect(isYearFolder(dirs[0]), true);
      expect(isYearFolder(dirs[1]), true);
      expect(isYearFolder(dirs[2]), false);
      expect(await isAlbumFolder(dirs[2]), true);
      expect(await isAlbumFolder(dirs[3]), false);
    });
    tearDownAll(() async {
      for (Directory d in dirs) {
        await d.delete();
      }
    });
  });

  /// This is complicated, thus those test are not bullet-proof
  group('Moving logic', () {
    final Directory output = Directory(
      join(Directory.systemTemp.path, '${basepath}testy-output'),
    );
    setUp(() async {
      await output.create();
      removeDuplicates(media, 40);
      findAlbums(media);
    });
    test('shortcut', () async {
      await moveFiles(
        media,
        output,
        copy: true,
        divideToDates: 0,
        albumBehavior: 'shortcut',
      ).toList();
      final Set<FileSystemEntity> outputted =
          await output.list(recursive: true, followLinks: false).toSet();
      // 2 folders + media + 1 album-ed shortcut
      expect(outputted.length, 2 + media.length + 1);
      if (Platform.isWindows) {
        expect(
          outputted
              .whereType<File>()
              .where((final File file) => file.path.endsWith('.lnk'))
              .length,
          1,
        );
      } else {
        expect(outputted.whereType<Link>().length, 1);
      }

      expect(
        outputted
            .whereType<Directory>()
            .map((final Directory e) => basename(e.path))
            .toSet(),
        <String>{'ALL_PHOTOS', 'Vacation'},
      );
    });
    test('nothing', () async {
      await moveFiles(
        media,
        output,
        copy: true,
        divideToDates: 0,
        albumBehavior: 'nothing',
      ).toList();
      final Set<FileSystemEntity> outputted =
          await output.list(recursive: true, followLinks: false).toSet();
      // 1 folder + media
      expect(outputted.length, 1 + media.length);
      expect(outputted.whereType<Link>().length, 0);
      expect(outputted.whereType<Directory>().length, 1);
      expect(
        outputted
            .whereType<Directory>()
            .map((final Directory e) => basename(e.path))
            .toSet(),
        <String>{'ALL_PHOTOS'},
      );
    });
    test('duplicate-copy', () async {
      await moveFiles(
        media,
        output,
        copy: true,
        divideToDates: 0,
        albumBehavior: 'duplicate-copy',
      ).toList();
      final Set<FileSystemEntity> outputted =
          await output.list(recursive: true, followLinks: false).toSet();
      // 2 folders + media + 1 album-ed copy
      expect(outputted.length, 2 + media.length + 1);
      expect(outputted.whereType<Link>().length, 0);
      expect(outputted.whereType<Directory>().length, 2);
      expect(outputted.whereType<File>().length, media.length + 1);
      expect(
        const UnorderedIterableEquality<String>().equals(
          outputted.whereType<File>().map((final File e) => basename(e.path)),
          <String>[
            'image-edited.jpg',
            'image-edited.jpg', // two times
            'Screenshot_2022-10-28-09-31-43-118_com.snapchat.jpg',
            'simple_file_20200101-edited(1).jpg',
            'Urlaub in Knaufspesch in der Schneifel (38).JPG',
            'img_(87).(vacation stuff).lol(87).jpg',
            'IMG-20150125-WA0003-modifié.jpg',
            'IMG-20150125-WA0003-modifié(1).jpg',
          ],
        ),
        true,
      );
      expect(
        outputted
            .whereType<Directory>()
            .map((final Directory e) => basename(e.path))
            .toSet(),
        <String>{'ALL_PHOTOS', 'Vacation'},
      );
    });

    test('json', () async {
      await moveFiles(
        media,
        output,
        copy: true,
        divideToDates: 0,
        albumBehavior: 'json',
      ).toList();
      final Set<FileSystemEntity> outputted =
          await output.list(recursive: true, followLinks: false).toSet();
      // 1 folder + media + 1 json
      expect(outputted.length, 1 + media.length + 1);
      expect(outputted.whereType<Link>().length, 0);
      expect(outputted.whereType<Directory>().length, 1);
      expect(outputted.whereType<File>().length, media.length + 1);
      expect(
        const UnorderedIterableEquality<String>().equals(
          outputted.whereType<File>().map((final File e) => basename(e.path)),
          <String>[
            'image-edited.jpg',
            'Screenshot_2022-10-28-09-31-43-118_com.snapchat.jpg',
            'simple_file_20200101-edited(1).jpg',
            'Urlaub in Knaufspesch in der Schneifel (38).JPG',
            'albums-info.json',
            'img_(87).(vacation stuff).lol(87).jpg',
            'IMG-20150125-WA0003-modifié.jpg',
            'IMG-20150125-WA0003-modifié(1).jpg',
          ],
        ),
        true,
      );
      expect(
        outputted
            .whereType<Directory>()
            .map((final Directory e) => basename(e.path))
            .toSet(),
        <String>{'ALL_PHOTOS'},
      );
    });
    tearDown(() async => output.delete(recursive: true));
  });

  group('isSupportedToWriteToExif', () {
    test('returns true for supported file formats', () {
      final supportedFiles = [
        File('test.jpg'),
        File('test.jpeg'),
        File('test.png'),
        File('test.gif'),
        File('test.bmp'),
        File('test.tiff'),
        File('test.tga'),
        File('test.pvr'),
        File('test.ico'),
      ];

      for (final file in supportedFiles) {
        expect(isSupportedToWriteToExif(file), isTrue);
      }
    });

    test('returns false for unsupported file formats', () {
      final unsupportedFiles = [
        File('test.txt'),
        File('test.pdf'),
        File('test.docx'),
        File('test.mp4'),
        File('test.json'),
      ];

      for (final file in unsupportedFiles) {
        expect(isSupportedToWriteToExif(file), isFalse);
      }
    });
  });

  group('writeGpsToExif', () {
    late File testImage;
    late DMSCoordinates testCoordinates;

    setUp(() {
      // Create a temporary test image file
      testImage = File('${basepath}test_image.jpg');
      testImage.writeAsBytesSync(
        encodeJpg(Image(width: 100, height: 100)),
      ); // Create a blank JPG image

      // Define test GPS coordinates
      testCoordinates = DMSCoordinates(
        latDegrees: 41,
        latMinutes: 19,
        latSeconds: 22.1611,
        longDegrees: 19,
        longMinutes: 48,
        longSeconds: 14.9139,
        latDirection: DirectionY.north,
        longDirection: DirectionX.east,
      );
    });

    tearDown(() {
      // Clean up the test image file
      if (testImage.existsSync()) {
        testImage.deleteSync();
      }
    });

    test('extracts GPS coordinates from valid JSON', () async {
      final result = await jsonCoordinatesExtractor(jsonFile6);

      expect(result, isNotNull);
      expect(result!.latSeconds, 19.779960000008714);
      expect(result.longSeconds, 53.690040000001886);
      expect(result.latDirection, DirectionY.north);
      expect(result.longDirection, DirectionX.east);
    });

    test('returns null for invalid JSON', () async {
      jsonFile6.writeAsStringSync('Invalid JSON');

      final result = await jsonCoordinatesExtractor(jsonFile6);

      expect(result, isNull);
    });

    test('returns null for missing GPS data', () async {
      jsonFile6.writeAsStringSync('{}');

      final result = await jsonCoordinatesExtractor(jsonFile6);

      expect(result, isNull);
    });

    test('writes GPS coordinates to EXIF metadata', () async {
      final bool result = await writeGpsToExif(testCoordinates, testImage);

      // Verify that the function returns true
      expect(result, isTrue);

      // Verify that the GPS coordinates were written to the EXIF metadata
      final Map<String, IfdTag> tags = await readExifFromFile(testImage);

      expect(tags['GPS GPSLatitude'], isNotNull);
      expect(tags['GPS GPSLongitude'], isNotNull);
      expect(tags['GPS GPSLatitudeRef']!.printable, 'N');
      expect(tags['GPS GPSLongitudeRef']!.printable, 'E');
    });

    test('returns false for unsupported file formats', () async {
      // Create a non-supported file format (e.g., a text file)
      final File unsupportedFile = File('${basepath}test_file.txt');
      unsupportedFile.writeAsStringSync('This is a test file.');

      final bool result = await writeGpsToExif(
        testCoordinates,
        unsupportedFile,
      );

      // Verify that the function returns false
      expect(result, isFalse);

      // Clean up the unsupported file
      unsupportedFile.deleteSync();
    });

    test('returns false for files with existing GPS EXIF data', () async {
      // Simulate a file with existing GPS EXIF data
      final Image? image = decodeJpg(testImage.readAsBytesSync());
      image!.exif.gpsIfd.gpsLatitude = testCoordinates.latSeconds;
      image.exif.gpsIfd.gpsLongitude = testCoordinates.longSeconds;
      final Uint8List newBytes = encodeJpg(image);
      testImage.writeAsBytesSync(newBytes);

      final bool result = await writeGpsToExif(testCoordinates, testImage);

      // Verify that the function returns false
      expect(result, isFalse);
    });

    test('returns false for invalid image files', () async {
      // Create a corrupted image file
      testImage.writeAsBytesSync(<int>[0, 1, 2, 3, 4]);

      final bool result = await writeGpsToExif(testCoordinates, testImage);

      // Verify that the function returns false
      expect(result, isFalse);
    });
  });

  group('writeDateTimeToExif', () {
    late File testImage;
    late DateTime testDateTime;

    setUp(() {
      // Create a temporary test image file
      testImage = File('${basepath}test_image.jpg');
      testImage.writeAsBytesSync(
        encodeJpg(Image(width: 100, height: 100)),
      ); // Create a blank JPG image

      // Define a test DateTime
      testDateTime = DateTime(
        2023,
        12,
        25,
        15,
        30,
        45,
      ); // Christmas Day, 3:30:45 PM
    });

    tearDown(() {
      // Clean up the test image file
      if (testImage.existsSync()) {
        testImage.deleteSync();
      }
    });

    test('writes DateTime to EXIF metadata', () async {
      final bool result = await writeDateTimeToExif(testDateTime, testImage);

      // Verify that the function returns true
      expect(result, isTrue);

      // Verify that the DateTime was written to the EXIF metadata
      final Uint8List bytes = await testImage.readAsBytes();
      final Map<String, IfdTag> tags = await readExifFromBytes(bytes);

      final DateFormat exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
      final String expectedDateTime = exifFormat.format(testDateTime);

      expect(tags['Image DateTime']!.printable, expectedDateTime);
      expect(tags['EXIF DateTimeOriginal']!.printable, expectedDateTime);
      expect(tags['EXIF DateTimeDigitized']!.printable, expectedDateTime);
    });

    test('returns false for unsupported file formats', () async {
      // Create a non-supported file format (e.g., a text file)
      final File unsupportedFile = File('test_file.txt');
      unsupportedFile.writeAsStringSync('This is a test file.');

      final bool result = await writeDateTimeToExif(
        testDateTime,
        unsupportedFile,
      );

      // Verify that the function returns false
      expect(result, isFalse);

      // Clean up the unsupported file
      unsupportedFile.deleteSync();
    });

    test('returns false for files with existing DateTime EXIF data', () async {
      // Simulate a file with existing DateTime EXIF data
      final Image? image = decodeJpg(testImage.readAsBytesSync());
      final DateFormat exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
      final String existingDateTime = exifFormat.format(
        DateTime(2020, 1, 1, 12),
      );
      image!.exif.imageIfd['DateTime'] = existingDateTime;
      image.exif.exifIfd['DateTimeOriginal'] = existingDateTime;
      image.exif.exifIfd['DateTimeDigitized'] = existingDateTime;
      final Uint8List newBytes = encodeJpg(image);
      testImage.writeAsBytesSync(newBytes);

      final bool result = await writeDateTimeToExif(testDateTime, testImage);

      // Verify that the function returns false
      expect(result, isFalse);
    });

    test('returns false for invalid image files', () async {
      // Create a corrupted image file
      testImage.writeAsBytesSync(<int>[0, 1, 2, 3, 4]);

      final bool result = await writeDateTimeToExif(testDateTime, testImage);

      // Verify that the function returns false
      expect(result, isFalse);
    });
  });

  /// Delete all shitty files as we promised
  tearDownAll(() {
    albumDir.deleteSync(recursive: true);
    imgFileGreen.deleteSync();
    imgFile1.deleteSync();
    imgFile2.deleteSync();
    imgFile3.deleteSync();
    imgFile4.deleteSync();
    imgFile4_1.deleteSync();
    imgFile5.deleteSync();
    imgFile6.deleteSync();
    imgFile6_1.deleteSync();
    jsonFile1.deleteSync();
    jsonFile2.deleteSync();
    jsonFile3.deleteSync();
    jsonFile4.deleteSync();
    jsonFile5.deleteSync();
    jsonFile6.deleteSync();
  });
}
