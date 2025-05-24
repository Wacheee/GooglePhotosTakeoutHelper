/// This file contains logic/utils for final act of moving actual files once
/// we have everything grouped, de-duplicated and sorted
// ignore_for_file: prefer_single_quotes

library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'interactive.dart' as interactive;
import 'media.dart';
import 'utils.dart';

/// This will add (1) add end of file name over and over until file with such
/// name doesn't exist yet. Will leave without "(1)" if is free already
File findNotExistingName(final File initialFile) {
  File file = initialFile;
  while (file.existsSync()) {
    file = File('${p.withoutExtension(file.path)}(1)${p.extension(file.path)}');
  }
  return file;
}

/// This will create symlink on unix and shortcut on windoza
///
/// Uses [findNotExistingName] for safety
///
/// WARN: Crashes with non-ascii names :(
Future<File> createShortcut(final Directory location, final File target) async {
  final String name =
      '${p.basename(target.path)}${Platform.isWindows ? '.lnk' : ''}';
  final File link = findNotExistingName(File(p.join(location.path, name)));
  // this must be relative to not break when user moves whole folder around:
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/232
  final String targetRelativePath =
      p.relative(target.path, from: link.parent.path);
  final String targetPath = target.absolute.path;
  if (Platform.isWindows) {
    try {
      await createShortcutWin(link.path, targetPath);
    } catch (e) {
      final ProcessResult res = await Process.run(
        'powershell.exe',
        <String>[
          '-ExecutionPolicy',
          'Bypass',
          '-NoLogo',
          '-NonInteractive',
          '-NoProfile',
          '-Command',
          "\$ws = New-Object -ComObject WScript.Shell; ",
          "\$s = \$ws.CreateShortcut(\"${link.path}\"); ",
          "\$s.TargetPath = \"$targetPath\"; ",
          "\$s.Save()",
        ],
      );
      if (res.exitCode != 0) {
        throw Exception('PowerShell doesnt work :( - \n\n'
            'report that to @TheLastGimbus on GitHub:\n\n'
            'https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues\n\n'
            '...or try other album solution\n'
            'sorry for inconvenience :('
            '\nshortcut exc -> $e');
      }
    }
    return File(link.path);
  } else {
    return File((await Link(link.path).create(targetRelativePath)).path);
  }
}

Future<File> moveFileAndCreateShortcut(
    final Directory newLocation, final File target) async {
  final String newPath = p.join(newLocation.path, p.basename(target.path));
  final File movedFile = await target.rename(
      newPath); // Move the file from year folder to album (new location)

  // Create shortcut in the original path (year folder)
  return createShortcut(target.parent, movedFile);
}

/// Big-ass logic of moving files from input to output
///
/// [allMediaFinal] should be nice, de-duplicated and album-ed etc
///
/// [copy] indicates whether to copy files or move them
///
/// [divideToDates] 1. One folder 2. Year folder 3. Year/Month 4. Year/Month/Day
///
/// [albumBehavior] must be one of [interactive.albumOptions]
///
/// Emits number of files that it copied/created/whatever (starting from 1) -
/// use [outputFileCount] function for progress measurement
Stream<int> moveFiles(
  final List<Media> allMediaFinal,
  final Directory output, {
  required final bool copy,
  required final num divideToDates,
  required final String albumBehavior,
}) async* {
  assert(interactive.albumOptions.keys.contains(albumBehavior), 
      'Invalid albumBehavior: $albumBehavior. Must be one of ${interactive.albumOptions.keys}');

  /// used only in 'json' behavior
  /// key = name of main outputted file | value = list of albums it belongs to
  final Map<String, List<String>> infoJson = <String, List<String>>{};
  int i = 0;
  for (final Media m in allMediaFinal) {
    // main file shortcuts will link to
    File? mainFile;

    final List<MapEntry<String?, File>> nullFirst = albumBehavior == 'json'
        // in 'json' case, we want to copy ALL files (like Archive) as normals
        ? <MapEntry<Null, File>>[
            MapEntry<Null, File>(null, m.files.values.first)
          ]
        // this will put null media first so album shortcuts can link to it
        : m.files.entries.sorted((final MapEntry<String?, File> a,
                final MapEntry<String?, File> b) =>
            (a.key ?? '').compareTo(b.key ?? ''));
    // iterate over all media of file to do something about them
    // ignore non-nulls with 'ignore', copy with 'duplicate-copy',
    // symlink with 'shortcut' etc
    for (final MapEntry<String?, File> file in nullFirst) {
      // if it's not from year folder and we're doing nothing/json, skip
      if (file.key != null &&
          <String>['nothing', 'json'].contains(albumBehavior)) {
        continue;
      }
      // now on, logic is shared for nothing+null/shortcut/copy cases
      final DateTime? date = m.dateTaken;
      String folderName;
      if (file.key != null) {
        folderName = file.key!.trim();
      } else {
        folderName = 'ALL_PHOTOS';
      }

      String dateFolder;
      if (date == null) {
        dateFolder = 'date-unknown';
      } else {
        if (divideToDates == 3) {
          dateFolder = p.join(
            '${date.year}',
            date.month.toString().padLeft(2, '0'),
            date.day.toString().padLeft(2, '0'),
          );
        } else if (divideToDates == 2) {
          dateFolder = p.join(
            '${date.year}',
            date.month.toString().padLeft(2, '0'),
          );
        } else if (divideToDates == 1) {
          dateFolder = '${date.year}';
        } else {
          dateFolder = '';
        }
      }

      final Directory folder = Directory(
        p.join(
          output.path,
          folderName,
          dateFolder,
        ),
      );
      // now folder logic is so complex i'll just create it every time 🤷
      await folder.create(recursive: true);

      /// result file/symlink to later change modify time
      File? result;

      /// moves/copies file with safe name
      // it's here because we do this for two cases
      Future<File> moveFile() async {
        final File freeFile = findNotExistingName(
            File(p.join(folder.path, p.basename(file.value.path))));
        try {
          return copy
              ? await file.value.copy(freeFile.path)
              : await file.value.rename(freeFile.path);
        } on FileSystemException {
          print(
            '[Step 7/8] [Error] Uh-uh, it looks like you selected another output drive than\n'
            "your input drive - gpth can't move files between them. But, you don't have\n"
            "to do this! Gpth *moves* files, so this doesn't take any extra space!\n"
            'Please run again and select different output location <3',
          );
          quit();
        }
      }

      if (file.key == null) {
        // if it's just normal "Photos from .." (null) file, just move it
        result = await moveFile();
        mainFile = result;
      } else if (albumBehavior == 'shortcut' && mainFile != null) {
        try {
          result = await createShortcut(folder, mainFile);
        } catch (e) {
          // in case powershell fails/whatever
          print('[Step 7/8] [Error] Creating shortcut for '
              '${p.basename(mainFile.path)} in ${p.basename(folder.path)} '
              'failed :(\n$e\n - copying normal file instead');
          result = await moveFile();
        }
      } else if (albumBehavior == 'reverse-shortcut' && mainFile != null) {
        try {
          result = await moveFileAndCreateShortcut(folder, mainFile);
        } catch (e) {
          if (e is FileSystemException) {
            //If file not exists its because is already moved to another album
            //Just copy the original to the album
            result = await moveFile();
          } else {
            // in case of other exception, print details
            print('[Step 7/8] [Error] Creating shortcut for '
                '${p.basename(mainFile.path)} in ${p.basename(folder.path)} '
                'failed :(\n$e\n - copying normal file instead');
            result = await moveFile();
          }
        }
      } else {
        // else - if we either run duplicate-copy or main file is missing:
        // (this happens with archive/trash/weird situation)
        // just copy it
        result = await moveFile();
      }

      // Done! Now, set the date:

      DateTime time = m.dateTaken ?? DateTime.now();
      if (Platform.isWindows && time.isBefore(DateTime(1970))) {
        print(
            '[Step 7/8] [Info]: ${m.firstFile.path} has date $time, which is before 1970 '
            '(not supported on Windows) - will be set to 1970-01-01');
        time = DateTime(1970);
      }
      try {
        await result.setLastModified(time);
      } on OSError catch (e) {
        // Sometimes windoza throws error but successes anyway 🙃:
        // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/229#issuecomment-1685085899
        // That's why this is here
        if (e.errorCode != 0) {
          print(
              "[Step 7/8] [Error]: Can't set modification time on $result: $e");
        }
      } catch (e) {
        log(
            "[Step 7/8]: Can't set modification time on $result: $e",level: 'warning'); //If error code 0, no need to notify user. Only log.
      }

      // one copy/move/whatever - one yield
      yield ++i;

      if (albumBehavior == 'json') {
        infoJson[p.basename(result.path)] = m.files.keys.nonNulls.toList();
      }
    }
    // done with this media - next!
  }
  if (albumBehavior == 'json') {
    await File(p.join(output.path, 'albums-info.json'))
        .writeAsString(jsonEncode(infoJson));
  }
}
