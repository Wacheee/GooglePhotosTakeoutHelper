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

/// Removes any media that match any of "extra" formats
/// Returns count of removed
int removeExtras(final List<Media> media) {
  final List<Media> copy = media.toList();
  int count = 0;
  for (final Media m in copy) {
    final String name = p.withoutExtension(p.basename(m.firstFile.path)).toLowerCase();
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
