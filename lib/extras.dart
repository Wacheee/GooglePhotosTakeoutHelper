import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'media.dart';

const List<String> extraFormats = <String>[
  // EN/US - thanks @DalenW
  '-edited',
  '-effects',
  '-smile',
  '-mix',
  // PL
  '-edytowane',
  // DE - thanks @cintx
  '-bearbeitet',
  // NL - thanks @jaapp
  '-bewerkt',
  // JA - thanks @fossamagna
  '-編集済み',
  // IT - thanks @rgstori
  '-modificato',
  // FR - for @palijn's problems <3
  '-modifié',
  // ES - @Sappstal report
  '-ha editado',
  // CA - @Sappstal report
  '-editat',
  // Add more "edited" flags in more languages if you want.
  // They need to be lowercase.
];

/// Removes media files that match "extra" format patterns (edited versions)
///
/// Filters out files with names ending in language-specific "edited" suffixes
/// like "-edited", "-bearbeitet", "-modifié", etc. Uses Unicode normalization
/// to handle accented characters correctly on macOS.
///
/// [media] List of Media objects to filter
/// Returns count of removed items
int removeExtras(final List<Media> media) {
  final List<Media> copy = media.toList();
  int count = 0;
  for (final Media m in copy) {
    final String name = p
        .withoutExtension(p.basename(m.firstFile.path))
        .toLowerCase();
    for (final String extra in extraFormats) {
      // MacOS uses NFD that doesn't work with our accents 🙃🙃
      // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
      if (unorm.nfc(name).endsWith(extra)) {
        media.remove(m);
        count++;
        break;
      }
    }
  }
  return count;
}

/// Checks if a filename matches "extra" format patterns (edited versions)
///
/// Returns true if the filename (without extension) ends with any language-specific
/// "edited" suffix like "-edited", "-bearbeitet", "-modifié", etc.
/// Uses Unicode normalization to handle accented characters correctly on macOS.
///
/// [filename] Filename to check (can include path and extension)
/// Returns true if the file appears to be an edited version
bool isExtra(final String filename) {
  final String name = p.withoutExtension(p.basename(filename)).toLowerCase();
  for (final String extra in extraFormats) {
    // MacOS uses NFD that doesn't work with our accents 🙃🙃
    // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
    if (unorm.nfc(name).endsWith(extra)) {
      return true;
    }
  }
  return false;
}
