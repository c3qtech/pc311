import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf_crypto/pdf_crypto.dart';

import '../io/js.dart' if (dart.library.io) '../io/vm.dart';
import '../pdf.dart';
import 'cross_ref_parser.dart';
import 'parsed_object.dart';

class PdfTools {
  PdfTools({
    DeflateCallback? deflate,
    bool compress = true,
    bool verbose = false,
    PdfVersion version = PdfVersion.pdf_1_5,
    String? author,
    String? creator,
    String? title,
    String? subject,
    String? keywords,
    String? producer,
  }) {
    settings = PdfSettings(
      deflate: compress ? (deflate ?? defaultDeflate) : null,
      verbose: verbose,
      version: version,
    );

    xref = PdfXrefTable();
    final rnd = math.Random.secure();
    final documentID = Uint8List.fromList(sha256
        .convert(DateTime.now().toIso8601String().codeUnits +
            List<int>.generate(32, (_) => rnd.nextInt(256)))
        .bytes);
    final id =
        PdfString(documentID, format: PdfStringFormat.binary, encrypted: false);
    xref.params['/ID'] = PdfArray([id, id]);

    catalog = PdfObjectBase(
      objser: _objser++,
      settings: settings,
      params: PdfDict.values(<String, PdfDataType>{
        '/Type': const PdfName('/Catalog'),
      }),
    );
    xref.objects.add(catalog);

    info = PdfObjectBase(
      objser: _objser++,
      settings: settings,
      params: PdfDict.values(<String, PdfDataType>{
        if (author != null) '/Author': PdfString.fromString(author),
        if (creator != null) '/Creator': PdfString.fromString(creator),
        if (title != null) '/Title': PdfString.fromString(title),
        if (subject != null) '/Subject': PdfString.fromString(subject),
        if (keywords != null) '/Keywords': PdfString.fromString(keywords),
        if (producer != null)
          '/Producer':
              PdfString.fromString('$producer (${PdfXrefTable.libraryName})')
        else
          '/Producer': PdfString.fromString(PdfXrefTable.libraryName),
        '/CreationDate': PdfString.fromDate(DateTime.now()),
      }),
    );
    xref.objects.add(info);
    xref.params['/Info'] = info.ref();

    kids = PdfArray<PdfIndirect>();
    pages = PdfObjectBase(
        objser: _objser++,
        settings: settings,
        params: PdfDict.values(<String, PdfDataType>{
          '/Type': const PdfName('/Pages'),
          '/Kids': kids,
        }));
    xref.objects.add(pages);

    catalog.params['/Pages'] = pages.ref();
  }

  late final PdfObjectBase<PdfDict> catalog;
  late final PdfObjectBase<PdfDict> info;
  late final PdfObjectBase<PdfDict> pages;
  late final PdfArray<PdfIndirect> kids;
  late final PdfXrefTable xref;
  late final PdfSettings settings;
  int _objser = 1;

  Uint8List save() {
    pages.params['/Count'] = PdfNum(kids.values.length);
    final os = PdfStream();
    xref.output(catalog, os);
    return os.output();
  }

  void addPages(
    PdfDocumentParser doc, {
    List<int>? pages,
  }) {
    final re = _ObjectRemapping(_objser);

    final pageList = pages == null ? doc.pages : pages.map((i) => doc.pages[i]);

    for (final page in pageList) {
      final pageObj = page.object;
      final newPage = PdfObjectBase(
        objser: re.nextObject(pageObj.objser),
        settings: settings,
        params: re.rewriteIndirects(pageObj.params),
      );
      (newPage.params as PdfDict)['/Parent'] = this.pages.ref();
      kids.add(newPage.ref());
      xref.objects.add(newPage);

      _walk(doc.xref, pageObj.params, {pageObj.objser}, (obj) {
        final params = obj.params;

        if (params is PdfDict) {
          if (params['/Type'] == const PdfName('/Pages')) {
            return false;
          }
        }

        final ob = PdfObjectBase(
          objser: re.nextObject(obj.objser),
          objgen: 0,
          settings: settings,
          params: re.rewriteIndirects(obj.params),
        );
        xref.objects.add(ob);
        return true;
      });
    }

    _objser = re._objser;
  }
}

typedef _WalkCb = bool Function(PdfParsedObject item);
typedef _WalkIndirect = PdfIndirect Function(PdfIndirect item);

class _ObjectRemapping {
  _ObjectRemapping(this._objser);

  int _objser;
  final _map = <int, int>{};

  void reset() {
    _map.clear();
  }

  PdfDataType rewriteIndirects(PdfDataType root) {
    return _rewriteIndirects(
      root,
      (a) => _PdfIndirect(_map, a.ser, 0),
    );
  }

  int nextObject(int original) {
    _map[original] = _objser;
    return _objser++;
  }

  PdfDataType _rewriteIndirects(
    PdfDataType root,
    _WalkIndirect cb,
  ) {
    var result = root;

    if (root is PdfDictStream) {
      final decoded = root.decode();
      final data = decoded.data;
      final isBinary = (data
          .any((e) => (e < 32 && e != 9 && e != 10 && e != 13) || e > 127));
      result = PdfDictStream(data: data, isBinary: isBinary);
      for (final item in root.values.entries) {
        if (item.key != '/Filter' && item.key != '/Length') {
          (result as PdfDict)[item.key] = _rewriteIndirects(item.value, cb);
        }
      }
      if (decoded.filters.length == 1) {
        (result as PdfDict)['/Filter'] = decoded.filters.first;
      } else if (decoded.filters.length > 1) {
        (result as PdfDict)['/Filter'] = PdfArray(decoded.filters);
      }
    } else if (root is PdfDict) {
      result = PdfDict();
      for (final item in root.values.entries) {
        (result as PdfDict)[item.key] = _rewriteIndirects(item.value, cb);
      }
    } else if (root is PdfArray) {
      result = PdfArray();
      for (final item in root.values) {
        (result as PdfArray).add(_rewriteIndirects(item, cb));
      }
    } else if (root is PdfIndirect) {
      result = cb(root);
    }
    return result;
  }
}

class _PdfIndirect extends PdfIndirect {
  const _PdfIndirect(this.map, int ser, int gen) : super(ser, gen);

  final Map<int, int> map;

  @override
  int get ser {
    try {
      return map[super.ser]!;
    } catch (_) {
      print('unable to find ${super.ser}');
      return 0;
    }
  }
}

void _walk(
  CrossRefTable xref,
  PdfDataType root,
  Set<int> seen,
  _WalkCb cb,
) {
  if (root is PdfDict) {
    for (final item in root.values.entries) {
      _walk(xref, item.value, seen, cb);
    }
  } else if (root is PdfArray) {
    for (final item in root.values) {
      _walk(xref, item, seen, cb);
    }
  } else if (root is PdfIndirect) {
    if (seen.contains(root.ser)) {
      return;
    }
    seen.add(root.ser);
    final PdfParsedObject<PdfDataType> item;
    try {
      item = xref.getObject(root);
    } catch (e) {
      print('Unable to find object $root');
      return;
    }
    if (cb(item)) {
      _walk(xref, item.params, seen, cb);
    }
  }
}
