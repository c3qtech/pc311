/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:convert';
import 'dart:typed_data';

/// Ascii HEX decoder
class AsciiHexDecoder extends Converter<Uint8List, Uint8List> {
  @override
  Uint8List convert(Uint8List input) {
    final output = Uint8List(input.length ~/ 2);

    var val = 0;
    var oe = false;
    var index = 0;
    for (final c in input) {
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        continue;
      }
      if (c == 0x3e) {
        break;
      }
      if (c >= 0x30 && c <= 0x39) {
        val = (val << 4) | (c - 0x30);
      } else if (c >= 0x41 && c <= 0x46) {
        val = (val << 4) | (c - 0x37);
      } else if (c >= 0x61 && c <= 0x66) {
        val = (val << 4) | (c - 0x57);
      } else {
        throw Exception('Unable to decode AsciiHexDecode filter');
      }
      if (!oe) {
        oe = true;
      } else {
        oe = false;
        output[index++] = val;
        val = 0;
      }
    }

    return output.sublist(0, index);
  }
}
