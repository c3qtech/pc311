import 'dart:convert';

import 'package:pdf/widgets.dart';
import 'package:pdf_crypto/src/pdf.dart';

import 'document.dart';

class PdfParsedFormField extends PdfFormField {
  PdfParsedFormField(this.parser, this.field, this.ref)
      : super(fieldType: '', rect: PdfRect.zero);

  final PdfDocumentParser parser;

  final PdfDict field;

  final PdfIndirect ref;

  @override
  String? get alternateName => field.containsKey('/TU')
      ? parser.resolve<PdfName>(field['/TU']!).value
      : null;

  @override
  String? get author => throw UnimplementedError();

  PdfDict get _mk => field.containsKey('/MK')
      ? parser.resolve<PdfDict>(field['/MK']!)
      : PdfDict();

  @override
  PdfColor? get backgroundColor => _mk.containsKey('/BG')
      ? _colorFrom(parser.resolve<PdfArray>(_mk['/BG']!).values)
      : null;

  @override
  PdfBorder? get border => throw UnimplementedError();

  @override
  PdfColor? get color => _mk.containsKey('/BC')
      ? _colorFrom(parser.resolve<PdfArray>(_mk['/BC']!).values)
      : null;

  @override
  String? get content => field.containsKey('/Contents')
      ? utf8.decode(parser.resolve<PdfString>(field['/Contents']!).value,
          allowMalformed: true)
      : null;

  @override
  DateTime? get date => throw UnimplementedError();

  @override
  Set<PdfFieldFlags>? get fieldFlags => throw UnimplementedError();

  @override
  int get fieldFlagsValue => field.containsKey('/Ff')
      ? parser.resolve<PdfNum>(field['/Ff']!).value.toInt()
      : 0;

  @override
  String? get fieldName => field.containsKey('/T')
      ? utf8.decode(parser.resolve<PdfString>(field['/T']!).value,
          allowMalformed: true)
      : null;

  @override
  String get fieldType => parser.resolve<PdfName>(field['/FT']!).value;

  @override
  int get flagValue => field.containsKey('/F')
      ? parser.resolve<PdfNum>(field['/F']!).value.toInt()
      : 0;

  @override
  Set<PdfAnnotFlags> get flags => throw UnimplementedError();

  @override
  PdfAnnotHighlighting? get highlighting {
    if (!field.containsKey('/H')) {
      return null;
    }

    switch (parser.resolve<PdfName>(field['/H']!).value) {
      case '/N':
        return PdfAnnotHighlighting.none;
      case '/I':
        return PdfAnnotHighlighting.invert;
      case '/O':
        return PdfAnnotHighlighting.outline;
      case '/P':
        return PdfAnnotHighlighting.push;
      case '/T':
        return PdfAnnotHighlighting.toggle;
    }

    return null;
  }

  @override
  String? get mappingName => field.containsKey('/TM')
      ? parser.resolve<PdfName>(field['/TM']!).value
      : null;

  @override
  String? get name => field.containsKey('/NM')
      ? parser.resolve<PdfName>(field['/NM']!).value
      : null;

  @override
  PdfRect get rect {
    final rectArray = parser.resolve<PdfArray>(field['/Rect']!);
    return PdfRect.fromLTRB(
      parser.resolve<PdfNum>(rectArray.values[0]).value.toDouble(),
      parser.resolve<PdfNum>(rectArray.values[1]).value.toDouble(),
      parser.resolve<PdfNum>(rectArray.values[2]).value.toDouble(),
      parser.resolve<PdfNum>(rectArray.values[3]).value.toDouble(),
    );
  }

  @override
  String? get subject => field.containsKey('/Subj')
      ? parser.resolve<PdfName>(field['/Subj']!).value
      : null;

  @override
  String get subtype => '/Widget';

  PdfIndirect get page => field['/P']! as PdfIndirect;

  PdfPage pageOfDocument(PdfDocument doc) {
    final localPage = page;
    return doc.pdfPageList.pages.firstWhere((e) => e.ref() == localPage);
  }

  PdfColor? _colorFrom(List<PdfDataType> values) {
    if (values.length == 4) {
      return PdfColorCmyk(
        parser.resolve<PdfNum>(values[0]).value.toDouble(),
        parser.resolve<PdfNum>(values[1]).value.toDouble(),
        parser.resolve<PdfNum>(values[2]).value.toDouble(),
        parser.resolve<PdfNum>(values[3]).value.toDouble(),
      );
    }
    if (values.length == 3) {
      return PdfColor(
        parser.resolve<PdfNum>(values[0]).value.toDouble(),
        parser.resolve<PdfNum>(values[1]).value.toDouble(),
        parser.resolve<PdfNum>(values[2]).value.toDouble(),
      );
    }

    return null;
  }

  @override
  String toString() =>
      '$runtimeType Type: $fieldType Name: $fieldName Page: $page Rect: $rect Content: $content';
}

class PdfParsedFormFieldText extends PdfParsedFormField {
  PdfParsedFormFieldText(
      PdfDocumentParser parser, PdfDict<PdfDataType> field, PdfIndirect ref)
      : super(parser, field, ref);

  void setContent(PdfDocument pdf, String value) {
    // Find the page in the pdf document
    final pdfPage = pageOfDocument(pdf);

    final rect = this.rect;

    // Draw something
    Widget.draw(
      TextField(
        name: fieldName!,
        color: color,
        // border: border,
        height: rect.height,
        width: rect.width,
        value: value,
        replaces: ref,
      ),
      offset: rect.offset,
      canvas: pdfPage.getGraphics(),
      page: pdfPage,
    );
  }
}

class PdfParsedFormFieldSign extends PdfParsedFormField {
  PdfParsedFormFieldSign(
      PdfDocumentParser parser, PdfDict<PdfDataType> field, PdfIndirect ref)
      : super(parser, field, ref);
}
