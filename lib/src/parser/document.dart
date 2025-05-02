/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:pkcs7/pkcs7.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

import '../pdf.dart';
import '../sign/signer.dart';
import 'cross_ref_parser.dart';
import 'form_field.dart';
import 'parsed_object.dart';
import 'parsed_page.dart';
import 'trailer_parser.dart';

/// PDF Document Parser used to load an existing document as a template for
/// modification
class PdfDocumentParser extends PdfDocumentParserBase {
  /// Create a PdfDocumentParser
  PdfDocumentParser(
    Uint8List bytes, {
    this.protectContents = false,
  }) : super(bytes) {
    // Find and Load the Cross Reference Table
    _prevXRef = trailerParser(bytes, bytes.length);
    xref = CrossRefTable(bytes, _prevXRef);
    // print(_xref);

    // Get the last object id
    final size = resolve<PdfNum>(xref.params.values['/Size']!);
    _objser = size.value.toInt();

    rootObject =
        xref.getObject<PdfDict>(xref.params.values['/Root']! as PdfIndirect);
    // Find the pages
    pageList = root.values['/Pages']! as PdfIndirect;
    _loadPages(pageList, null);

    if (root.containsKey('/PageLabels')) {
      _loadPageLabels(resolve<PdfDict>(root.values['/PageLabels']!));
    } else {
      pageLabels = null;
    }

    if (root.containsKey('/AcroForm')) {
      acroForm = resolve<PdfDict>(root.values['/AcroForm']!);
    } else {
      acroForm = null;
    }
  }

  late final int _objser;

  @override
  int get size => _objser;

  late final int _prevXRef;

  @override
  int get xrefOffset => _prevXRef;

  late final PdfParsedObject<PdfDict> rootObject;

  PdfDict get root => rootObject.params;

  late final CrossRefTable xref;

  late final PdfIndirect pageList;

  final pages = <ParsedPage>[];

  /// Save the graphic state
  final bool protectContents;

  late final PdfDict? acroForm;

  late final Map<int, PdfPageLabel>? pageLabels;

  final graphicStates = PdfDict();

  @override
  PdfVersion get version => xref.version;

  T resolve<T extends PdfDataType>(PdfDataType ref) {
    return xref.resolve<T>(ref);
  }

  void _loadPages(PdfDataType page, PdfArray? mediaBox) {
    int? objser;
    var objgen = 0;

    if (page is PdfIndirect) {
      objser = page.ser;
      objgen = page.gen;
      page = resolve<PdfDict>(page);
    }

    if (page is PdfDict) {
      final type = resolve<PdfName>(page.values['/Type']!);
      if (type.value == '/Pages') {
        if (page.values.containsKey('/MediaBox')) {
          mediaBox = resolve<PdfArray>(page.values['/MediaBox']!);
        }
        final kids = resolve<PdfArray>(page.values['/Kids']!);

        for (final p in kids.values) {
          _loadPages(p, mediaBox);
        }
      } else if (type.value == '/Page') {
        pages.add(
            ParsedPage(parser: this, page: page, ser: objser, gen: objgen));
        if (page.containsKey('/Resources')) {
          final resources = resolve<PdfDict>(page['/Resources']!);

          // page['/Resources'] = resources;

          // Resolve resources
          for (final name in resources.values.keys) {
            resources[name] = resolve<PdfDataType>(resources[name]!);
          }

          if (resources.containsKey('/ExtGState')) {
            final extGState = resources['/ExtGState']! as PdfDict;
            graphicStates.addAll(extGState);
          }
        }

        if (!page.containsKey('/MediaBox') && mediaBox != null) {
          page['/MediaBox'] = mediaBox;
        }

        // if (page.containsKey('/Annots')) {
        // final annotations = _resolve<PdfArray>(page['/Annots']!) as PdfArray;
        // page.values.remove('/Annots');
        // }
      }
    }
  }

  void _loadPageLabels(PdfDict pl) {
    pageLabels = <int, PdfPageLabel>{};
    if (pl.containsKey('/Kids')) {
      for (final child in resolve<PdfArray>(pl.values['/Kids']!).values) {
        _loadPageLabels(resolve<PdfDict>(child));
      }
    }
    if (pl.containsKey('/Nums')) {
      var tic = true;
      var id = -1;
      for (final entry in resolve<PdfArray>(pl.values['/Nums']!).values) {
        if (tic) {
          id = resolve<PdfNum>(entry).value.toInt();
          tic = false;
          continue;
        }

        final d = resolve<PdfDict>(entry).values;
        final p = d.containsKey('/P')
            ? utf8.decode(resolve<PdfString>(d['/P']!).value,
                allowMalformed: true)
            : null;
        final st = d.containsKey('/St')
            ? resolve<PdfNum>(d['/St']!).value.toInt()
            : null;
        final PdfPageLabelStyle? s;
        switch (d.containsKey('/S') ? resolve<PdfName>(d['/S']!).value : null) {
          case '/D':
            s = PdfPageLabelStyle.arabic;
            break;
          case '/R':
            s = PdfPageLabelStyle.romanUpper;
            break;
          case '/r':
            s = PdfPageLabelStyle.romanLower;
            break;
          case '/A':
            s = PdfPageLabelStyle.lettersUpper;
            break;
          case '/a':
            s = PdfPageLabelStyle.lettersLower;
            break;
          default:
            s = null;
        }

        pageLabels![id] = (PdfPageLabel(p, style: s, subsequent: st));
        tic = true;
      }
    }
  }

  void _makeDirect(PdfDict dict, String key) {
    if (dict.containsKey(key) && dict[key]! is PdfIndirect) {
      final a = resolve(dict[key]!);
      dict[key] = a;
    }
  }

  @override
  void mergeDocument(PdfDocument pdfDocument) {
    final currentCatalog = xref.params.values['/Root']!;
    if (currentCatalog is! PdfIndirect) {
      throw Exception('The Root object is not indirect');
    }

    final newPageList =
        PdfPageList(pdfDocument, objser: pageList.ser, objgen: pageList.gen);
    newPageList.params.merge(resolve<PdfDict>(pageList));

    // Import the catalog
    pdfDocument.catalog = PdfCatalog(pdfDocument, newPageList,
        objser: currentCatalog.ser, objgen: currentCatalog.gen);
    pdfDocument.catalog.params.merge(root);

    late PdfObjectStream pre;
    late PdfObjectStream post;

    if (protectContents) {
      pre = PdfObjectStream(pdfDocument)..buf.putString('q');
      post = PdfObjectStream(pdfDocument)..buf.putString('Q');
    }

    for (final page in pages) {
      _makeDirect(page.page, '/Annots');
      _makeDirect(page.page, '/MediaBox');
      _makeDirect(page.page, '/Rotate');
      _makeDirect(page.page, '/Resources');

      var format = PdfPageFormat.standard;
      if (page.page.containsKey('/MediaBox')) {
        final mb = resolve<PdfArray>(page.page['/MediaBox']!);
        format = PdfPageFormat(
          (mb.values[2] as PdfNum).value.toDouble(),
          (mb.values[3] as PdfNum).value.toDouble(),
        );
      }

      final p = PdfPage(
        pdfDocument,
        pageFormat: format,
        objser: page.ser,
        objgen: page.gen,
      );

      if (page.page['/Contents'] is PdfIndirect) {
        // Check if it's a PdfArrayObject
        final content = resolve(page.page['/Contents']!);
        if (content is PdfArray) {
          page.page['/Contents'] = content;
        }
      }

      if (protectContents) {
        if (page.page['/Contents'] is! PdfArray) {
          page.page['/Contents'] =
              PdfArray([page.page['/Contents'] as PdfIndirect]);
        }
        final content = page.page['/Contents'] as PdfArray;
        content.values.insert(0, pre.ref());
        content.values.add(post.ref());
      }
      p.params.merge(page.page);
    }

    if (graphicStates.isNotEmpty) {
      pdfDocument.graphicStates.params.addAll(graphicStates);
    }

    if (acroForm != null) {
      pdfDocument.catalog.params['/AcroForm'] = acroForm!;
    }

    if (pageLabels != null) {
      pdfDocument.catalog.pageLabels = PdfPageLabels(pdfDocument)
        ..labels.addAll(pageLabels!);
    }
  }

  /// Verify if the document has been modified since the last signature
  void verifySignature(List<X509> trusted) {
    if (!root.containsKey('/AcroForm')) {
      throw Exception('No form found');
    }

    final form = resolve<PdfDict>(root.values['/AcroForm']!);

    if (!form.containsKey('/Fields')) {
      throw Exception('No fields found');
    }

    final fields = resolve<PdfArray>(form.values['/Fields']!);

    var found = false;
    for (final field in fields.values.map(resolve).whereType<PdfDict>()) {
      if (!field.containsKey('/FT') ||
          (resolve<PdfName>(field['/FT']!)).value != '/Sig' ||
          !field.containsKey('/V')) {
        continue;
      }

      final signature = resolve<PdfDict>(field.values['/V']!);
      _verifySignature(signature, trusted);

      found = true;
    }

    if (!found) {
      throw Exception('No signature widget found');
    }
  }

  void _verifySignature(PdfDict signature, List<X509> trusted) {
    if (!signature.containsKey('/ByteRange')) {
      throw Exception('No ByteRange found');
    }

    final range = resolve<PdfArray>(signature.values['/ByteRange']!);
    final xRange = Iterable<PdfSignRange>.generate(
      range.values.length ~/ 2,
      (i) {
        final start = range.values[i * 2] as PdfNum;
        final end = range.values[i * 2 + 1] as PdfNum;

        return PdfSignRange(
          start.value.toInt(),
          end.value.toInt(),
        );
      },
    );

    if (!signature.containsKey('/Filter')) {
      throw Exception('No Filter found');
    }

    final filter = resolve<PdfName>(signature.values['/Filter']!);
    if (filter.value != '/Adobe.PPKLite') {
      throw Exception('Unsupported signature: $filter');
    }

    if (!signature.containsKey('/SubFilter')) {
      throw Exception('No SubFilter found');
    }

    final subFilter = resolve<PdfName>(signature.values['/SubFilter']!);

    if (!signature.containsKey('/Contents')) {
      throw Exception('No SubFilter found');
    }

    final contents = resolve<PdfString>(signature.values['/Contents']!);

    if (subFilter.value == '/adbe.pkcs7.detached') {
      final pkcs7 = Pkcs7.fromDer(contents.value);
      final si = pkcs7.verify(trusted);
      final algo = si.getDigest(si.digestAlgorithm);
      final digest = Uint8List(algo.digestSize);
      for (final r in xRange) {
        algo.update(bytes, r.start, r.length);
      }
      algo.doFinal(digest, 0);

      if (!si.listEquality(digest, si.messageDigest!)) {
        throw Exception('The file has been modified');
      }
      return;
    }

    if (subFilter.value == '/adbe.x509.rsa_sha1') {
      final cert = resolve<PdfDataType>(signature.values['/Cert']!);
      final certs = <X509>[];
      if (cert is PdfArray) {
        for (final c in cert.values) {
          certs.add(X509.fromDer((c as PdfString).value));
        }
      } else {
        certs.add(X509.fromDer((cert as PdfString).value));
      }

      final encryptedSignature = ASN1Parser(contents.value).nextObject();
      final errors = <String>[];

      for (final c in certs) {
        final param = PublicKeyParameter<RSAPublicKey>(c.publicKey);
        final rsa = PKCS1Encoding(RSAEngine());
        rsa.init(false, param);
        try {
          final s = rsa.process(encryptedSignature.valueBytes!);
          final signature = ASN1Parser(s).nextObject() as ASN1Sequence;
          final param = signature.elements![0] as ASN1Sequence;
          final oi = param.elements![0] as ASN1ObjectIdentifier;
          final sign = signature.elements![1] as ASN1OctetString;
          final signAlgo = c.commonDigestAlgorithm(oi);
          final algo = c.getDigest(signAlgo);
          final digest = Uint8List(algo.digestSize);
          for (final r in xRange) {
            algo.update(bytes, r.start, r.length);
          }
          algo.doFinal(digest, 0);

          if (!c.listEquality(digest, sign.octets!)) {
            throw Exception('The file has been modified');
          }

          c.verifyChain(<X509>[...certs.where((e) => e != c)], trusted);
          return;
        } catch (e) {
          errors.add(e.toString());
        }
      }

      throw Exception(
          'The signature is invalid${errors.isNotEmpty ? ' (${errors.join(', ')}' : ''}');
    }

    throw Exception('Signature not found');
  }

  Iterable<PdfParsedFormField> get acroFormFields sync* {
    if (acroForm == null) {
      return;
    }

    final fields = resolve<PdfArray>(acroForm!['/Fields']!);

    for (final fieldId in fields.values) {
      final ref = fieldId as PdfIndirect;
      final field = resolve<PdfDict>(ref);
      if (field['/Subtype'] == const PdfName('/Widget')) {
        if (!field.containsKey('/P')) {
          var found = false;
          for (final page in pages) {
            final annotations =
                resolve<PdfArray>(page.page['/Annots'] ?? PdfArray());
            if (annotations.values.contains(ref)) {
              field['/P'] = page.ref;
              found = true;
              break;
            }
          }
          if (!found) {
            continue;
          }
        }
        switch (resolve<PdfName>(field['/FT']!).value) {
          case '/Tx':
            yield PdfParsedFormFieldText(this, field, ref);
            break;
          case '/Sig':
            yield PdfParsedFormFieldSign(this, field, ref);
            break;
          default:
            yield PdfParsedFormField(this, field, ref);
        }
      }
    }
  }
}
