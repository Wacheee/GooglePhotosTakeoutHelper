import 'dart:ffi';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:proper_filesize/proper_filesize.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:win32/win32.dart';
import 'interactive.dart' as interactive;
import 'media.dart';

// remember to bump this
const String version = '4.0.0';

/// max file size to read for exif/hash/anything
const int maxFileSize = 64 * 1024 * 1024;

//initialising some global variables
bool isVerbose = false;

bool enforceMaxFileSize = false;

bool exifToolInstalled = false;

/// convenient print for errors
void error(final Object? object) => stderr.write('$object\n');

Never quit([final int code = 1]) {
  if (interactive.indeed) {
    print(
      '[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - '
      'press enter to close]',
    );
    stdin.readLineSync();
  }
  exit(code);
}

extension X on Iterable<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Iterable<File> wherePhotoVideo() => whereType<File>().where((final File e) {
    final String mime = lookupMimeType(e.path) ?? '';
    final String fileExtension = p.extension(e.path).toLowerCase();
    return mime.startsWith('image/') ||
        mime.startsWith('video/') ||
        // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/223
        // https://github.com/dart-lang/mime/issues/102
        // 🙃🙃
        mime == 'model/vnd.mts' ||
        _moreExtensions.contains(fileExtension);
  });
}

extension Y on Stream<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Stream<File> wherePhotoVideo() => whereType<File>().where((final File e) {
    final String mime = lookupMimeType(e.path) ?? '';
    final String fileExtension = p.extension(e.path).toLowerCase();
    return mime.startsWith('image/') ||
        mime.startsWith('video/') ||
        // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/223
        // https://github.com/dart-lang/mime/issues/102
        // 🙃🙃
        mime == 'model/vnd.mts' ||
        _moreExtensions.contains(fileExtension);
  });
}

//Support raw formats (dng, cr2) and Pixel motion photos (mp, mv)
const List<String> _moreExtensions = <String>['.mp', '.mv', '.dng', '.cr2'];

extension Util on Stream {
  Stream<T> whereType<T>() => where((final e) => e is T).cast<T>();
}

Future<int?> getDiskFree([String? path]) async {
  path ??= Directory.current.path;
  if (Platform.isLinux) {
    return _dfLinux(path);
  } else if (Platform.isWindows) {
    return _dfWindoza(path);
  } else if (Platform.isMacOS) {
    return _dfMcOS(path);
  } else {
    return null;
  }
}

Future<int?> _dfLinux(final String path) async {
  final ProcessResult res = await Process.run('df', <String>[
    '-B1',
    '--output=avail',
    path,
  ]);
  return res.exitCode != 0
      ? null
      : int.tryParse(
        res.stdout.toString().split('\n').elementAtOrNull(1) ?? '',
        radix: 10, // to be sure
      );
}

Future<int?> _dfWindoza(final String path) async {
  final String driveLetter = p
      .rootPrefix(p.absolute(path))
      .replaceAll('\\', '')
      .replaceAll(':', '');
  final ProcessResult res = await Process.run('powershell', <String>[
    '-Command',
    'Get-PSDrive -Name ${driveLetter[0]} | Select-Object -ExpandProperty Free',
  ]);
  final int? result = res.exitCode != 0 ? null : int.tryParse(res.stdout);
  return result;
}

Future<int?> _dfMcOS(final String path) async {
  final ProcessResult res = await Process.run('df', <String>['-k', path]);
  if (res.exitCode != 0) return null;
  final String? line2 = res.stdout.toString().split('\n').elementAtOrNull(1);
  if (line2 == null) return null;
  final List<String> elements = line2.split(' ')
    ..removeWhere((final String e) => e.isEmpty);
  final int? macSays = int.tryParse(
    elements.elementAtOrNull(3) ?? '',
    radix: 10, // to be sure
  );
  return macSays != null ? macSays * 1024 : null;
}

String filesize(final int bytes) => FileSize.fromBytes(bytes).toString(
  unit: Unit.auto(size: bytes, baseType: BaseType.metric),
  decimals: 2,
);

int outputFileCount(final List<Media> media, final String albumOption) {
  if (<String>[
    'shortcut',
    'duplicate-copy',
    'reverse-shortcut',
  ].contains(albumOption)) {
    return media.fold(
      0,
      (final int prev, final Media e) => prev + e.files.length,
    );
  } else if (albumOption == 'json') {
    return media.length;
  } else if (albumOption == 'nothing') {
    return media.where((final Media e) => e.files.containsKey(null)).length;
  } else {
    throw ArgumentError.value(albumOption, 'albumOption');
  }
}

extension Z on String {
  /// Returns same string if pattern not found
  String replaceLast(final String from, final String to) {
    final int lastIndex = lastIndexOf(from);
    if (lastIndex == -1) return this;
    return replaceRange(lastIndex, lastIndex + from.length, to);
  }
}

Future<void> renameIncorrectJsonFiles(final Directory directory) async {
  int renamedCount = 0;
  await for (final FileSystemEntity entity in directory.list(recursive: true)) {
    if (entity is File && p.extension(entity.path) == '.json') {
      final String originalName = p.basename(entity.path);

      // Regex to dettect pattern
      final RegExp regex = RegExp(
        r'^(.*\.[a-z0-9]{3,5})\..+\.json$',
        caseSensitive: false,
      );

      final RegExpMatch? match = regex.firstMatch(originalName);
      if (match != null) {
        final String newName = '${match.group(1)}.json';
        if (newName != originalName) {
          final String newPath = p.join(p.dirname(entity.path), newName);
          final File newFile = File(newPath);

          // Verify if the file renamed already exists
          if (await newFile.exists()) {
            log(
              '[Step 1/8] Skipped renaming of json because it already exists: $newPath',
            );
          } else {
            try {
              await entity.rename(newPath);
              renamedCount++;
              log('[Step 1/8] Renamed: ${entity.path} -> $newPath');
            } on FileSystemException catch (e) {
              log(
                '[Step 1/8] While renaming json ${entity.path}: ${e.message}',
                level: 'error',
              );
            }
          }
        }
      }
    }
  }
  print(
    '[Step 1/8] Successfully renamed JSON files (suffix removed): $renamedCount',
  );
}

Future<void> changeMPExtensions(
  final List<Media> allMedias,
  final String finalExtension,
) async {
  int renamedCount = 0;
  for (final Media m in allMedias) {
    for (final MapEntry<String?, File> entry in m.files.entries) {
      final File file = entry.value;
      final String ext = p.extension(file.path).toLowerCase();
      if (ext == '.mv' || ext == '.mp') {
        final String originalName = p.basenameWithoutExtension(file.path);
        final String normalizedName = unorm.nfc(originalName);

        final String newName = '$normalizedName$finalExtension';
        if (newName != normalizedName) {
          final String newPath = p.join(p.dirname(file.path), newName);
          // Rename file and update reference in map
          try {
            final File newFile = await file.rename(newPath);
            m.files[entry.key] = newFile;
            renamedCount++;
          } on FileSystemException catch (e) {
            print(
              '[Step 6/8] [Error] Error changing extension to $finalExtension -> ${file.path}: ${e.message}',
            );
          }
        }
      }
    }
  }
  print(
    '[Step 6/8] Successfully changed Pixel Motion Photos files extensions (change it to $finalExtension): $renamedCount',
  );
}

/// Recursively traverses the output [directory] and updates
/// the creation time of files in batches.
/// For each file, attempts to set the creation date to match
/// the last modification date.
/// Only Windows support for now, using PowerShell.
//TODO In the future MacOS support is possible if the user has XCode installed
Future<int> updateCreationTimeRecursively(final Directory directory) async {
  if (!Platform.isWindows) {
    print(
      '[Step 8/8] Skipping: Updating creation time is only supported on Windows.',
    );
    return 0;
  }
  int changedFiles = 0;
  const int maxChunkSize =
      32000; //Avoid 32768 char limit in command line with chunks

  String currentChunk = '';
  await for (final FileSystemEntity entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      //Command for each file
      final String command =
          "(Get-Item '${entity.path}').CreationTime = (Get-Item '${entity.path}').LastWriteTime;";
      //If current command + chunk is larger than 32000, commands in currentChunk is executed and current comand is passed for the next execution
      if (currentChunk.length + command.length > maxChunkSize) {
        final bool success = await _executePShellCreationTimeCmd(currentChunk);
        if (success) {
          changedFiles +=
              currentChunk.split(';').length - 1; // -1 to ignore last ';'
        }
        currentChunk = command;
      } else {
        currentChunk += command;
      }
    }
  }

  //Leftover chunk is executed after the for
  if (currentChunk.isNotEmpty) {
    final bool success = await _executePShellCreationTimeCmd(currentChunk);
    if (success) {
      changedFiles +=
          currentChunk.split(';').length - 1; // -1 to ignore last ';'
    }
  }
  print(
    '[Step 8/8] Successfully updated creation time for $changedFiles files!',
  );
  return changedFiles;
}

//Execute a chunk of commands in PowerShell related with creation time
Future<bool> _executePShellCreationTimeCmd(final String commandChunk) async {
  try {
    final ProcessResult result = await Process.run('powershell', <String>[
      '-ExecutionPolicy',
      'Bypass',
      '-NonInteractive',
      '-Command',
      commandChunk,
    ]);

    if (result.exitCode != 0) {
      print(
        '[Step 8/8] Error updateing creation time in batch: ${result.stderr}',
      );
      return false;
    }
    return true;
  } catch (e) {
    print('[Step 8/8] Error updating creation time: $e');
    return false;
  }
}

Future<void> createShortcutWin(
  final String shortcutPath,
  final String targetPath,
) async {
  Pointer<COMObject>? shellLink;
  Pointer<COMObject>? persistFile;
  Pointer<Utf16>? shortcutPathPtr;
  Pointer<Utf16>? targetPathPtr;

  try {
    // Initialize COM
    final hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hrInit)) {
      throw Exception('Error initializing COM: $hrInit');
    }

    // Allocate COM objects
    shellLink = calloc<COMObject>();
    if (shellLink.address == 0) {
      throw Exception('Failed to allocate shellLink');
    }

    // Create IShellLink instance
    final hr = CoCreateInstance(
        GUIDFromString(CLSID_ShellLink).cast<GUID>(),
        nullptr,
        CLSCTX_INPROC_SERVER,
        GUIDFromString(IID_IShellLink).cast<GUID>(),
        shellLink.cast());

    if (FAILED(hr)) {
      throw Exception('Error creating IShellLink instance: $hr');
    }

    final shellLinkPtr = IShellLink(shellLink);
    targetPathPtr = targetPath.toNativeUtf16();
    if (targetPathPtr.address == 0) {
      throw Exception('Failed to allocate targetPathPtr');
    }
    shellLinkPtr.setPath(targetPathPtr.cast());

    // Query IPersistFile
    persistFile = calloc<COMObject>();
    if (persistFile.address == 0) {
      throw Exception('Failed to allocate persistFile');
    }
    final hrPersistFile = shellLinkPtr.queryInterface(
        GUIDFromString(IID_IPersistFile).cast<GUID>(),
        persistFile.cast());
    if (FAILED(hrPersistFile)) {
      throw Exception('Error obtaining IPersistFile: $hrPersistFile');
    }

    final persistFilePtr = IPersistFile(persistFile);
    shortcutPathPtr = shortcutPath.toNativeUtf16();
    if (shortcutPathPtr.address == 0) {
      throw Exception('Failed to allocate shortcutPathPtr');
    }
    final hrSave = persistFilePtr.save(shortcutPathPtr.cast(), TRUE);
    if (FAILED(hrSave)) {
      throw Exception('Error saving shortcut: $hrSave');
    }
  } finally {
    // Cleanup
    if (shortcutPathPtr != null && shortcutPathPtr.address != 0) {
      free(shortcutPathPtr);
    }
    if (targetPathPtr != null && targetPathPtr.address != 0) {
      free(targetPathPtr);
    }
    if (persistFile != null && persistFile.address != 0) {
      IPersistFile(persistFile).release();
      free(persistFile);
    }
    if (shellLink != null && shellLink.address != 0) {
      IShellLink(shellLink).release();
      free(shellLink);
    }
    CoUninitialize();
  }
}

///This little helper function replaces the default log function, so it can be used with compiled code and a -v argument
///Default log level is 'info'. Possible values for 'level' are: 'error', 'warning' and 'info'
void log(final String message, {final String level = 'info'}) {
  if (isVerbose) {
    final String color;
    switch (level.toLowerCase()) {
      case 'error':
        color = '\x1B[31m'; // Red for errors
        break;
      case 'warning':
        color = '\x1B[33m'; // Yellow for warnings
        break;
      case 'info':
      default:
        color = '\x1B[32m'; // Green for info
        break;
    }
    print(
      '$color[${level.toUpperCase()}] $message\x1B[0m',
    ); // Reset color after the message
  }
}
