/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'package:archive/archive.dart';

import '../pdf.dart';

/// ZLib inflate function
List<int> zLibInflate(List<int> data) {
  return const ZLibDecoder().decodeBytes(data);
}

/// Zip compression function
DeflateCallback defaultDeflate = const ZLibEncoder().encode;
