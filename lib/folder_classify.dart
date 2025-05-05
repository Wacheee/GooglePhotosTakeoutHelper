/// This file contains utils for determining type of a folder
/// Whether it's a legendary "year folder", album, trash, etc
library;
import 'dart:io';

import 'package:path/path.dart' as p;

import 'utils.dart';

bool isYearFolder(final Directory dir) =>
    RegExp(r'^Photos from (20|19|18)\d{2}$').hasMatch(p.basename(dir.path));

Future<bool> isAlbumFolder(final Directory dir) =>
    dir.parent.list().whereType<Directory>().any(isYearFolder);
