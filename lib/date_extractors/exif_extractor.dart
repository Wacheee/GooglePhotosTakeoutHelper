import 'dart:io';
import 'dart:math' as math;
import 'package:exif_reader/exif_reader.dart';
import 'package:ffmpeg_cli/ffmpeg_cli.dart';
import 'package:mime/mime.dart';
import '../utils.dart';

/// DateTime from exif data *potentially* hidden within a [file]
///
/// You can try this with *any* file, it either works or not 🤷
/// You should only use this function after checking wherePhotoVideo() on the File(s) for performance reasons.
Future<DateTime?> exifDateTimeExtractor(final File file) async {
  //If file is >maxFileSize - return null. https://github.com/brendan-duncan/image/issues/457#issue-1549020643
  if (await file.length() > maxFileSize && enforceMaxFileSize) {
    log(
      '[Step 4/8] The file is larger than the maximum supported file size of ${maxFileSize.toString()} bytes. File: ${file.path}',
      level: 'error',
    );
    return null;
  }

  //Getting mimeType.
  final String? mimeType = lookupMimeType(file.path);

  //Now we need to see what we got and depending on what we got, we need to handle it quite differently.
  switch (mimeType) {
    case null: // if lookupMimeType does not support file type
      log(
        '[Step 4/8] MimeType is null, which means we do not support reading from Exif for the filetype of file: ${file.path}',
        level: 'error',
      );
      return null;
    case final String _
        when mimeType.startsWith('image/'): //If file is an image
      // NOTE: reading whole file may seem slower than using readExifFromFile
      // but while testing it was actually 2x faster (confirmed on different devices)
      final bytes = await file.readAsBytes();
      // this returns empty {} if file doesn't have exif so don't worry
      final tags = await readExifFromBytes(bytes);
      String? datetime;
      // try if any of these exists
      datetime ??= tags['Image DateTime']?.printable;
      datetime ??= tags['EXIF DateTimeOriginal']?.printable;
      datetime ??= tags['EXIF DateTimeDigitized']?.printable;
      if (datetime == null) return null;
      // replace all shitty separators that are sometimes met
      datetime = datetime
          .replaceAll('-', ':')
          .replaceAll('/', ':')
          .replaceAll('.', ':')
          .replaceAll('\\', ':')
          .replaceAll(': ', ':0')
          .substring(0, math.min(datetime.length, 19))
          .replaceFirst(':', '-') // replace two : year/month to comply with iso
          .replaceFirst(':', '-');
      // now date is like: "1999-06-23 23:55"
      return DateTime.tryParse(datetime);
    case final String _
        when ((mimeType.startsWith('video/')) ||
            (mimeType.startsWith(
              'model/vnd.mts',
            ))): //If file is a video (mts is handled seperately because it's weird and different (can you relate?) :P)
      if (ffProbeInstalled) {
        //ffprobe is available

        FfprobeResult? ffprobeResult;
        try {
          //running ffprobe
          ffprobeResult = await Ffprobe.run(file.path);
        } catch (e) {
          log(
            '[Step 4/8] Extracting DateTimeCreated EXIF value with ffprobe failed. Is ffprobe present locally and in \$PATH variable? Error: ${e.toString()}',
            level: 'error',
          );
          return null;
        }
        final String? videoCreationDateTimeString =
            ffprobeResult.format?.tags?.creationTime;
        if (videoCreationDateTimeString != null) {
          final DateTime videoCreationDateTime = DateTime.parse(
            videoCreationDateTimeString,
          );
          log(
            '[Step 4/8] Extracted DateTime from EXIF through ffprobe for ${file.path}',
          );
          return videoCreationDateTime;
        } else {
          //if the video file was decoded by ffprobe, but it did not contain a DateTime in CreationTime
          log(
            '[Step 4/8] Extracted null DateTime from EXIF through ffprobe for ${file.path}. This is expected behaviour if your video file does not contain a CreationDate.', level: 'warning');
          return null;
        }
      }
      log('[Step 4/8] Skipping getting DateTime because ffprobe is not installed for ${file.path}');
      return null; //if ffprobe is not installed and file is video
    default: //if it's not an image or video or null or too large.
      //if it's not an image or video or null or too large.
      log(
        '[Step 4/8] MimeType ${lookupMimeType(file.path)} is not handled yet. Please create an issue if you encounter this error, as we should handle whatever you got there. This happened for file: ${file.path}',level: 'error' //Satisfies wherePhotoVideo() but is not image/ or video/ mime type.
      );
      return null;
  }
}
