import 'dart:typed_data';

import 'package:pdf/widgets.dart';
import 'package:pdf_crypto/src/pdf.dart';

import '../parser/document.dart';

extension PdfDocumentAppender on PdfDocument {
  PdfDocumentParser get parser => prev as PdfDocumentParser;

  /// This writes the document to an OutputStream.
  Future<void> _write(PdfStream os) async {
    PdfSignature? signature;

    final xref = PdfXrefTable(lastObjectId: objser);

    for (final ob in objects.where((e) => e.inUse)) {
      if (ob is PdfSignature) {
        assert(signature == null, 'Only one document signature is allowed');
        signature = ob;
      } else if (ob == catalog) {
        continue;
      } else if (pdfPageList.pages.contains(ob)) {
        continue;
      } else if (ob == pdfPageList) {
        continue;
      }
      xref.objects.add(ob);
    }

    // Add pages
    for (final page in pdfPageList.pages) {
      if (page.annotations.isNotEmpty) {
        final originalPage = parser.xref.getObject(
          page.ref(),
          settings: settings,
        );

        final res = _updateKey(xref, originalPage.params as PdfDict, '/Annots',
            PdfArray(page.annotations.map((e) => e.ref())), false);
        if (res) {
          xref.objects.add(originalPage);
        }
      }
    }

    final id =
        PdfString(documentID, format: PdfStringFormat.binary, encrypted: false);
    xref.params['/ID'] = PdfArray([id, id]);
    xref.params['/Prev'] = PdfNum(parser.xrefOffset);

    if (catalog.params.containsKey('/AcroForm')) {
      final origCatalog = parser.xref.getObject(
        catalog.ref(),
        settings: settings,
      );

      var res = _updateKey(xref, origCatalog.params as PdfDict, '/AcroForm',
          catalog.params['/AcroForm']!, true);
      if (signature?.value.hasMDP ?? false) {
        if (_updateKey(xref, origCatalog.params as PdfDict, '/Perms',
            catalog.params['/Perms'] ?? PdfDict(), true)) {
          res = true;
        }
      }
      if (res) {
        xref.objects.add(origCatalog);
      }
    }

    xref.output(catalog, os);

    if (signature != null) {
      await signature.writeSignature(os);
    }
  }

  bool _updateValue(
      PdfXrefTable xref, PdfDataType params, PdfDataType value, bool replace) {
    if (params is PdfDict && value is PdfDict) {
      var res = false;
      for (final key in value.values.keys) {
        if (_updateKey(xref, params, key, value[key]!, replace)) {
          res = true;
        }
      }
      return res;
    }
    if (!replace && params is PdfArray && value is PdfArray) {
      var res = false;
      for (final key in value.values) {
        if (!params.values.contains(key)) {
          params.add(key);
          res = true;
        }
      }
      return res;
    }

    return true;
  }

  bool _updateKey(PdfXrefTable xref, PdfDict params, String key,
      PdfDataType value, bool replace) {
    if (!params.containsKey(key)) {
      params[key] = value;
      return true;
    } else if (params[key] is PdfIndirect) {
      final child = parser.xref
          .getObject((params[key] as PdfIndirect), settings: settings);
      final res = _updateValue(xref, child.params, value, replace);
      if (res) {
        final newChild = PdfObjectBase(
            objser: child.objser,
            objgen: child.objgen,
            settings: settings,
            params: value);
        xref.objects.add(newChild);
      }
      return false;
    } else {
      return _updateValue(xref, params[key]!, value, replace);
    }
  }

  /// Generate the PDF document as a memory file
  Future<Uint8List> appendSignatureOnly() async {
    assert(prev != null, 'Load a document first');

    final os = PdfStream();
    os.putBytes(parser.bytes);
    await _write(os);
    return os.output();
  }
}

extension DocumentAppender on Document {
  /// Generate the PDF document as a memory file
  Future<Uint8List> appendSignatureOnly() async {
    await save();
    return await document.appendSignatureOnly();
  }
}
