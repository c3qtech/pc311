/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import '../pdf.dart';
import 'data_types_parser.dart';

class PdfParsedObject<T extends PdfDataType> extends PdfObjectBase<T> {
  PdfParsedObject({
    required int objser,
    int objgen = 0,
    required this.data,
    PdfSettings settings = const PdfSettings(verbose: true),
  }) : super(
          objser: objser,
          objgen: objgen,
          params: data.data as T,
          settings: settings,
        );

  final PdfParsedDataType data;
}
