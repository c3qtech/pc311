/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

Uint8List unPredict(Uint8List data, int rowBytes, int bpp) {
  assert(rowBytes > 0);

  Uint8List? prevRow;
  var output = 0;

  for (var index = 0;
      index + rowBytes + 1 <= data.length;
      index += rowBytes + 1) {
    final row = data.sublist(index + 1, index + 1 + rowBytes);
    _unfilter(data[index], bpp, row, prevRow);
    data.setRange(output, output + rowBytes, row);
    prevRow = data.sublist(output, output + rowBytes);
    output += rowBytes;
  }

  return data.sublist(0, output);
}

Uint8List unPredictFixed(int predictor, Uint8List data, int rowBytes, int bpp) {
  assert(rowBytes > 0);

  Uint8List? prevRow;
  var output = 0;

  for (var index = 0; index + rowBytes <= data.length; index += rowBytes) {
    final row = data.sublist(index, index + rowBytes);
    _unfilter(predictor, bpp, row, prevRow);
    data.setRange(output, output + rowBytes, row);
    prevRow = data.sublist(output, output + rowBytes);
    output += rowBytes;
  }

  return data.sublist(0, output);
}

// https://github.com/brendan-duncan/image/blob/d2968da8f0519189f5f599634390cba20d0f04e1/lib/src/formats/png_decoder.dart#L663
void _unfilter(int filterType, int bpp, Uint8List row, Uint8List? prevRow) {
  final rowBytes = row.length;

  switch (filterType) {
    case 0:
      break;
    case 1:
      for (var x = bpp; x < rowBytes; ++x) {
        row[x] = (row[x] + row[x - bpp]) & 0xff;
      }
      break;
    case 2:
      for (var x = 0; x < rowBytes; ++x) {
        final b = prevRow != null ? prevRow[x] : 0;
        row[x] = (row[x] + b) & 0xff;
      }
      break;
    case 3:
      for (var x = 0; x < rowBytes; ++x) {
        final a = x < bpp ? 0 : row[x - bpp];
        final b = prevRow != null ? prevRow[x] : 0;
        row[x] = (row[x] + ((a + b) >> 1)) & 0xff;
      }
      break;
    case 4:
      for (var x = 0; x < rowBytes; ++x) {
        final a = x < bpp ? 0 : row[x - bpp];
        final b = prevRow != null ? prevRow[x] : 0;
        final c = x < bpp || prevRow == null ? 0 : prevRow[x - bpp];

        final p = a + b - c;

        final pa = (p - a).abs();
        final pb = (p - b).abs();
        final pc = (p - c).abs();

        var paeth = 0;
        if (pa <= pb && pa <= pc) {
          paeth = a;
        } else if (pb <= pc) {
          paeth = b;
        } else {
          paeth = c;
        }

        row[x] = (row[x] + paeth) & 0xff;
      }
      break;
    default:
      throw Exception('Invalid filter value: $filterType');
  }
}
