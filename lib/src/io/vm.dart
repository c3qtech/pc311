/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:io';

import '../pdf.dart';

/// ZLib inflate function
List<int> zLibInflate(List<int> data) {
  return ZLibDecoder().convert(data);
}

/// Zip compression function
DeflateCallback defaultDeflate = zlib.encode;
