/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:convert';
import 'dart:typed_data';

/// Ascii 85 decoder
class Ascii85Decoder extends Converter<Uint8List, Uint8List> {
  @override
  Uint8List convert(Uint8List input) {
    final output = Uint8List(_maxDecodedLen(input.length));

    var value = 0;
    var nb = 0;
    var outputOffset = 0;

    for (var index = 0; index < input.length; index++) {
      final b = input[index];

      if (b <= 0x20) {
        continue;
      } else if (b == 0x7a && nb == 0) {
        nb = 5;
        value = 0;
      } else if (0x21 <= b && b <= 0x75) {
        value = value * 85 + b - 0x21;
        nb++;
      } else if (b == 0x7e &&
          index < input.length + 1 &&
          input[index + 1] == 0x3e) {
        index++;
        continue;
      } else {
        throw Exception('Corrupted ASCII85 data');
      }

      if (nb == 5) {
        output[outputOffset] = (value >> 24) & 0xff;
        output[outputOffset + 1] = (value >> 16) & 0xff;
        output[outputOffset + 2] = (value >> 8) & 0xff;
        output[outputOffset + 3] = value & 0xff;
        outputOffset += 4;
        nb = 0;
        value = 0;
      }
    }

    if (nb > 0) {
      // The number of output bytes in the last fragment
      // is the number of leftover input bytes - 1:
      // the extra byte provides enough bits to cover
      // the inefficiency of the encoding for the block.
      if (nb == 1) {
        throw Exception('Corrupted ASCII85 data');
      }

      for (var i = nb; i < 5; i++) {
        // The short encoding truncated the output value.
        // We have to assume the worst case values (digit 84)
        // in order to ensure that the top bits are correct.
        value = value * 85 + 84;
      }

      for (var i = 0; i < nb - 1; i++) {
        output[outputOffset] = (value >> 24) & 0xff;
        value <<= 8;
        outputOffset++;
      }
    }

    return output.sublist(0, outputOffset);
  }

  int _maxDecodedLen(int length) => length;
}
