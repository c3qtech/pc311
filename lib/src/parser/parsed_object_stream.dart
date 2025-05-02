/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import '../io/js.dart' if (dart.library.io) '../io/vm.dart';
import '../pdf.dart';
import 'ascii85.dart';
import 'ascii_hex.dart';
import 'lzw_decoder.dart';
import 'png_predictor.dart';

extension PdfParsedObjectStream on PdfDictStream {
  Uint8List? _decodeFilter(String filter, Uint8List data) {
    switch (filter) {
      case '/ASCII85Decode':
        return Ascii85Decoder().convert(data);
      case '/ASCIIHexDecode':
        return AsciiHexDecoder().convert(data);
      case '/FlateDecode':
        var decoded = Uint8List.fromList(zLibInflate(data));
        final decodeParams = values['/DecodeParms'];
        if (decodeParams is PdfDict) {
          final columns =
              (decodeParams['/Columns'] as PdfNum?)?.value.toInt() ?? 1;
          final colors =
              (decodeParams['/Colors'] as PdfNum?)?.value.toInt() ?? 1;
          final predictor =
              (decodeParams['/Predictor'] as PdfNum?)?.value.toInt() ?? 1;
          final bpp =
              (decodeParams['/BitsPerComponent'] as PdfNum?)?.value.toInt() ??
                  8;
          if (predictor == 1) {
            return decoded;
          }

          assert(predictor >= 10 && predictor <= 16);

          decoded = unPredict(decoded, (colors * columns * bpp + 7) >> 3,
              (bpp * colors + 7) >> 3);

          values.remove('/DecodeParms');
        }

        return decoded;
      case '/LZWDecode':
        final decoder = LzwDecoder();
        final output = decoder.convert(data);
        var decoded = Uint8List.fromList(output);
        final decodeParams = values['/DecodeParms'];
        if (decodeParams is PdfDict) {
          final columns =
              (decodeParams['/Columns'] as PdfNum?)?.value.toInt() ?? 1;
          final colors =
              (decodeParams['/Colors'] as PdfNum?)?.value.toInt() ?? 1;
          final predictor =
              (decodeParams['/Predictor'] as PdfNum?)?.value.toInt() ?? 1;
          if (predictor == 1) {
            return decoded;
          }

          assert(predictor >= 10 && predictor <= 16);
          decoded = unPredict(decoded, colors * columns, 1);
        }

        return decoded;

      case '/DCTDecode': // Jpeg
        return null;

      case '/CCITTFaxDecode':
        return null; // TIFF Image
    }
    throw Exception('Unknown filter: $filter');
  }

  PdfDecodedStream decode() {
    final filter = values['/Filter'];
    if (filter == null) {
      return PdfDecodedStream(data);
    }

    if (filter is PdfName) {
      final result = _decodeFilter(filter.value, data);
      if (result == null) {
        return PdfDecodedStream(data, [filter]);
      }
      return PdfDecodedStream(result);
    } else if (filter is PdfArray) {
      var val = data;
      var count = 0;
      for (final subFilter in filter.values) {
        if (subFilter is PdfName) {
          final result = _decodeFilter(subFilter.value, val);
          if (result == null) {
            return PdfDecodedStream(val,
                filter.values.sublist(count).map((e) => e as PdfName).toList());
          } else {
            val = result;
          }
        } else {
          throw Exception('Unable to decode sub filter stream: $subFilter');
        }

        count++;
      }
      return PdfDecodedStream(val);
    }

    throw Exception('Unable to decode stream: $filter');
  }
}

class PdfDecodedStream {
  PdfDecodedStream(this.data, [this.filters = const []]);

  final Uint8List data;
  final List<PdfName> filters;
}
