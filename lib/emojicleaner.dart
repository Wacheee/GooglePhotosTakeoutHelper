import 'dart:io';
import 'package:emoji_regex/emoji_regex.dart' as r;
import 'package:path/path.dart' as p;
import 'utils.dart';

/// Encodes emoji characters in the album directory name to hex representation and renames the folder on disk if needed.
///
/// [albumDir] The Directory whose name may contain emoji characters.
/// Returns the new (possibly hex-encoded) directory.
Directory encodeAndRenameAlbumIfEmoji(final Directory albumDir) {
  final String originalName = p.basename(albumDir.path);

  if (!r.emojiRegex().hasMatch(originalName) &&
      !RegExp(r'\u{FE0F}|\u{FE0E}', unicode: true).hasMatch(originalName)) {
    //Check for emojis or invisible character
    return albumDir;
  }

  log('Found an emoji in ${albumDir.path}. Encoding it to hex.');
  final String parentPath = albumDir.parent.path;
  final StringBuffer cleanName = StringBuffer();

  for (int i = 0; i < originalName.length; i++) {
    final int codeUnit = originalName.codeUnitAt(i);
    final String char = String.fromCharCode(codeUnit);

    // Handle surrogate pairs
    if (codeUnit >= 0xD800 &&
        codeUnit <= 0xDBFF &&
        i + 1 < originalName.length) {
      final int nextCodeUnit = originalName.codeUnitAt(i + 1);
      if (nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF) {
        final int emoji =
            ((codeUnit - 0xD800) << 10) + (nextCodeUnit - 0xDC00) + 0x10000;
        cleanName.write('_0x${emoji.toRadixString(16)}_');
        i++;
        continue;
      }
    }

    // Handle BMP emoji
    if (r.emojiRegex().hasMatch(char) ||
        RegExp(r'\u{FE0F}|\u{FE0E}', unicode: true).hasMatch(char)) {
      cleanName.write('_0x${codeUnit.toRadixString(16)}_');
    } else {
      cleanName.write(char);
    }
  }

  final String newPath = p.join(parentPath, cleanName.toString());
  if (albumDir.path != newPath) {
    try {
      albumDir.renameSync(newPath);
    } catch (e) {
      Exception(
        'Error while trying to rename directory with emoji. Does not Exist!',
      );
    }
  }
  return Directory(newPath);
}

/// Decodes hex-encoded emoji sequences back to emoji characters.
///
/// [encodedPath] The path with hex-encoded emojis in the last segment.
/// Returns the path with emojis restored, or the original path if no encoding present.
String decodeAndRestoreAlbumEmoji(final String encodedPath) {
  final List<String> parts = encodedPath.split(p.separator);
  if (parts.isEmpty) return encodedPath;

  // Only decode if hex-encoded emoji is present in the last segment
  if (RegExp(r'_0x[0-9a-fA-F]+_').hasMatch(parts.last)) {
    log(
      'Found a hex encoded emoji in $encodedPath. Decoding it back to emoji.',
    );
    parts[parts.length - 1] = _decodeEmojiComponent(parts.last);
    return parts.join(p.separator);
  }
  return encodedPath;
}

/// Internal helper function to decode hex-encoded emoji characters back to UTF-8.
///
/// Processes strings containing patterns like "_0x1f600_" and converts them
/// back to their corresponding Unicode characters.
///
/// [component] A string potentially containing hex-encoded emojis
/// Returns the string with all hex-encoded emojis converted back to UTF-8
String _decodeEmojiComponent(final String component) {
  final RegExp emojiPattern = RegExp(r'_0x([0-9a-fA-F]+)_');
  return component.replaceAllMapped(emojiPattern, (final Match match) {
    final int codePoint = int.parse(match.group(1)!, radix: 16);
    return String.fromCharCode(codePoint);
  });
}
