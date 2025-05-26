import 'dart:ffi';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:gpth/interactive.dart' as interactive;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:proper_filesize/proper_filesize.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'media.dart';

// remember to bump this
const version = '3.4.3';

/// max file size to read for exif/hash/anything
const maxFileSize = 64 * 1024 * 1024;

/// convenient print for errors
void error(Object? object) => stderr.write('$object\n');

Never quit([int code = 1]) {
  if (interactive.indeed) {
    print('[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - '
        'press enter to close]');
    stdin.readLineSync();
  }
  exit(code);
}

extension X on Iterable<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Iterable<File> wherePhotoVideo() => whereType<File>().where((e) {
        final mime = lookupMimeType(e.path) ?? "";
        final fileExtension = p.extension(e.path).toLowerCase();
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
  Stream<File> wherePhotoVideo() => whereType<File>().where((e) {
        final mime = lookupMimeType(e.path) ?? "";
        final fileExtension = p.extension(e.path).toLowerCase();
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
const _moreExtensions = ['.mp', '.mv', '.dng', '.cr2'];

extension Util on Stream {
  Stream<T> whereType<T>() => where((e) => e is T).cast<T>();
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

Future<int?> _dfLinux(String path) async {
  final res = await Process.run('df', ['-B1', '--output=avail', path]);
  return res.exitCode != 0
      ? null
      : int.tryParse(
          res.stdout.toString().split('\n').elementAtOrNull(1) ?? '',
          radix: 10, // to be sure
        );
}

Future<int?> _dfWindoza(String path) async {
  final res = await Process.run('wmic', [
    'LogicalDisk',
    'Where',
    'DeviceID="${p.rootPrefix(p.absolute(path)).replaceAll('\\', '')}"',
    'Get',
    'FreeSpace'
  ]);
  return res.exitCode != 0
      ? null
      : int.tryParse(
          res.stdout.toString().split('\n').elementAtOrNull(1) ?? '',
        );
}

Future<int?> _dfMcOS(String path) async {
  final res = await Process.run('df', ['-k', path]);
  if (res.exitCode != 0) return null;
  final line2 = res.stdout.toString().split('\n').elementAtOrNull(1);
  if (line2 == null) return null;
  final elements = line2.split(' ')..removeWhere((e) => e.isEmpty);
  final macSays = int.tryParse(
    elements.elementAtOrNull(3) ?? '',
    radix: 10, // to be sure
  );
  return macSays != null ? macSays * 1024 : null;
}

String filesize(int bytes) => ProperFilesize.generateHumanReadableFilesize(
      bytes,
      base: Bases.Binary,
      decimals: 2,
    );

int outputFileCount(List<Media> media, String albumOption) {
  if (['shortcut', 'duplicate-copy', 'reverse-shortcut']
      .contains(albumOption)) {
    return media.fold(0, (prev, e) => prev + e.files.length);
  } else if (albumOption == 'json') {
    return media.length;
  } else if (albumOption == 'nothing') {
    return media.where((e) => e.files.containsKey(null)).length;
  } else {
    throw ArgumentError.value(albumOption, 'albumOption');
  }
}

extension Z on String {
  /// Returns same string if pattern not found
  String replaceLast(String from, String to) {
    final lastIndex = lastIndexOf(from);
    if (lastIndex == -1) return this;
    return replaceRange(lastIndex, lastIndex + from.length, to);
  }
}

Future<void> renameIncorrectJsonFiles(Directory directory) async {
  int renamedCount = 0;
  final goodJsonRegex = RegExp(
    r'^(.+)\.(.+?)(\(.+?\))*\.json$',
    caseSensitive: false,
  );

  final regex = RegExp(
    r'^(.+?)(\.[a-z0-9]{3,5})\..*?(\(.+?\))*\.json$',
    caseSensitive: false,
  );
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && p.extension(entity.path) == '.json') {
      final originalName = p.basename(entity.path);

      // Regex to dettect pattern
      /* 
      img.jpg.supple(18).json
      img.jpg.json
      img.jpg(1).json
      img.jpg..(1).json

      group(1) = img
      group(2) = .jpg
      group(3) = (1)      
      */

      File? newFile;
      // most common case - faster processing
      if (originalName.endsWith(".supplemental-metadata.json")) {
        // easy solve
        final newName =
            originalName.replaceLast('.supplemental-metadata.json', '.json');
        final newPath = p.join(p.dirname(entity.path), newName);
        newFile = File(newPath);
      } else {
        // search for pattern
        final match = regex.firstMatch(originalName);
        if (match != null) {
          var newName = originalName;
          if (match.group(3) == null) {
            newName = '${match.group(1)}${match.group(2)}.json';
          } else {
            newName =
                '${match.group(1)}${match.group(2)}${match.group(3)}.json';
          }

          // so, there is something that should be done
          if (newName != originalName) {
            // let's check if the file is already in the good format
            final goodJsonMatch = goodJsonRegex.firstMatch(originalName);
            if (goodJsonMatch != null) {
              File goodJsonFile = File(p.join(entity.parent.path,
                  '${goodJsonMatch.group(1)}${goodJsonMatch.group(3)}.${goodJsonMatch.group(2)}'));
              if (!goodJsonFile.existsSync()) {
                final newPath = p.join(p.dirname(entity.path), newName);
                newFile = File(newPath);
              }
            } else {
              final newPath = p.join(p.dirname(entity.path), newName);
              newFile = File(newPath);
            }
          }
        }
      }

      // Verify if the file renamed already exists
      if (newFile != null) {
        if (newFile.existsSync()) {
          print('[Renamed] Skipping: $newFile already exists');
        } else {
          try {
            await entity.rename(newFile.path);
            renamedCount++;
            //print('[Renamed] ${entity.path} -> $newPath');
          } on FileSystemException catch (e) {
            print('[Error] Renaming ${entity.path}: ${e.message}');
          }
        }
      }
    }
  }
  print('Successfully renamed JSON files (suffix removed): $renamedCount');
}

Future<void> changeMPExtensions(
    List<Media> allMedias, String finalExtension) async {
  int renamedCount = 0;
  for (final m in allMedias) {
    for (final entry in m.files.entries) {
      final file = entry.value;
      final ext = p.extension(file.path).toLowerCase();
      if (ext == '.mv' || ext == '.mp') {
        final originalName = p.basenameWithoutExtension(file.path);
        final normalizedName = unorm.nfc(originalName);

        final newName = '$normalizedName$finalExtension';
        if (newName != normalizedName) {
          final newPath = p.join(p.dirname(file.path), newName);
          // Rename file and update reference in map
          try {
            final newFile = await file.rename(newPath);
            m.files[entry.key] = newFile;
            renamedCount++;
          } on FileSystemException catch (e) {
            print(
                '[Error] Error changing extension to $finalExtension -> ${file.path}: ${e.message}');
          }
        }
      }
    }
  }
  print(
      'Successfully changed Pixel Motion Photos files extensions (change it to $finalExtension): $renamedCount');
}

/// Recursively traverses the output [directory] and updates
/// the creation time of files in batches.
/// For each file, attempts to set the creation date to match
/// the last modification date.
/// Only Windows support for now, using PowerShell.
/// In the future MacOS support is possible if the user has XCode installed
Future<void> updateCreationTimeRecursively(Directory directory) async {
  if (!Platform.isWindows) {
    print("Skipping: Updating creation time is only supported on Windows.");
    return;
  }
  int changedFiles = 0;
  int maxChunkSize = 32000; //Avoid 32768 char limit in command line with chunks

  String currentChunk = "";
  await for (final entity
      in directory.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      //Command for each file
      final command =
          "(Get-Item '${entity.path}').CreationTime = (Get-Item '${entity.path}').LastWriteTime;";
      //If current command + chunk is larger than 32000, commands in currentChunk is executed and current comand is passed for the next execution
      if (currentChunk.length + command.length > maxChunkSize) {
        bool success = await _executePShellCreationTimeCmd(currentChunk);
        if (success)
          changedFiles +=
              currentChunk.split(';').length - 1; // -1 to ignore last ';'
        currentChunk = command;
      } else {
        currentChunk += command;
      }
    }
  }

  //Leftover chunk is executed after the for
  if (currentChunk.isNotEmpty) {
    bool success = await _executePShellCreationTimeCmd(currentChunk);
    if (success)
      changedFiles +=
          currentChunk.split(';').length - 1; // -1 to ignore last ';'
  }
  print("Successfully updated creation time for $changedFiles files!");
}

//Execute a chunk of commands in PowerShell related with creation time
Future<bool> _executePShellCreationTimeCmd(String commandChunk) async {
  try {
    final result = await Process.run('powershell', [
      '-ExecutionPolicy',
      'Bypass',
      '-NonInteractive',
      '-Command',
      commandChunk
    ]);

    if (result.exitCode != 0) {
      print("Error updateing creation time in batch: ${result.stderr}");
      return false;
    }
    return true;
  } catch (e) {
    print("Error updating creation time: $e");
    return false;
  }
}

void createShortcutWin(String shortcutPath, String targetPath) {
  Pointer<COMObject>? shellLink;
  Pointer<COMObject>? persistFile;
  Pointer<Utf16>? shortcutPathPtr;
  try {
    // Initialize the COM library on the current thread
    final hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hrInit)) {
      throw ('Error initializing COM: $hrInit');
    }

    shellLink = calloc<COMObject>();

    // Create IShellLink instance
    final hr = CoCreateInstance(
        GUIDFromString(CLSID_ShellLink).cast<GUID>(),
        nullptr,
        CLSCTX_INPROC_SERVER,
        GUIDFromString(IID_IShellLink).cast<GUID>(),
        shellLink.cast());

    if (FAILED(hr)) {
      throw ('Error creating IShellLink instance: $hr');
    }

    final shellLinkPtr = IShellLink(shellLink);
    shellLinkPtr.SetPath(targetPath.toNativeUtf16().cast());

    // Saving shortcut
    persistFile = calloc<COMObject>();
    final hrPersistFile = shellLinkPtr.QueryInterface(
        GUIDFromString(IID_IPersistFile).cast<GUID>(), persistFile.cast());
    if (FAILED(hrPersistFile)) {
      throw ('Error obtaining IPersistFile: $hrPersistFile');
    }
    final persistFilePtr = IPersistFile(persistFile);
    shortcutPathPtr = shortcutPath.toNativeUtf16();
    final hrSave = persistFilePtr.Save(shortcutPathPtr.cast(), TRUE);

    if (FAILED(hrSave)) {
      throw ('Error trying to save shortcut: $hrSave');
    }
  } finally {
    // Free memory
    if (shortcutPathPtr != null) {
      free(shortcutPathPtr);
    }
    if (persistFile != null) {
      IPersistFile(persistFile).Release();
      free(persistFile);
    }
    if (shellLink != null) {
      IShellLink(shellLink).Release();
      free(shellLink);
    }
    CoUninitialize();
  }
}
