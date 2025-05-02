/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import '../pdf.dart';
import 'cross_ref_parser.dart';
import 'data_types_parser.dart';
import 'parsed_object.dart';
import 'parsed_object_stream.dart';

class PdfCompressedObjects {
  PdfCompressedObjects(this.objects, this.data, this.xref);

  final Map<int, int> objects;

  final Uint8List data;

  final CrossRefTable xref;

  PdfParsedObject<T> getObject<T extends PdfDataType>(
    int ser, {
    PdfSettings settings = const PdfSettings(verbose: true),
  }) {
    assert(objects.containsKey(ser));

    final params = pdfStreamParser(data, objects[ser]!, xref);

    return PdfParsedObject<T>(
      objser: ser,
      objgen: 0,
      data: params,
      settings: settings,
    );
  }
}

PdfCompressedObjects parseCompressedObjects(
    PdfParsedObject<PdfDictStream> container, CrossRefTable xref) {
  assert(container.params['/Type'] == const PdfName('/ObjStm'));

  final first = (container.params['/First'] as PdfNum).value.toInt();
  final count = (container.params['/N'] as PdfNum).value.toInt();
  final data = container.params.decode().data;

  final obj = <int, int>{};
  var offset = 0;
  while (obj.length < count) {
    final startObject = offset;
    while (data[offset] >= 0x30 && data[offset] <= 0x39) {
      offset++;
    }
    final objectNumber =
        String.fromCharCodes(data.sublist(startObject, offset));
    final startOffset = offset;
    offset++;
    while (data[offset] >= 0x30 && data[offset] <= 0x39) {
      offset++;
    }
    final objectOffset =
        String.fromCharCodes(data.sublist(startOffset, offset));
    obj[int.parse(objectNumber)] = int.parse(objectOffset) + first;
    offset++;
  }

  return PdfCompressedObjects(obj, data, xref);
}
