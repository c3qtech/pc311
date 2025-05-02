/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import 'package:pem/pem.dart';
import 'package:pkcs7/pkcs7.dart';
import 'package:pointycastle/asn1.dart';

import '../pdf.dart';
import 'pkcs7_signer.dart';
import 'rsa_signer.dart';
import 'signer.dart';

/// The access permissions granted for this document.
enum PdfSignPerms {
  /// No changes to the document shall be permitted.
  /// Any change to the document shall invalidate the signature.
  none,

  /// Permitted changes shall be filling in forms, instantiating page templates,
  /// and signing. Other changes shall invalidate the signature.
  partial,

  /// Permitted changes shall be the same as for 2, as well as annotation creation, deletion, and modification. Other changes shall invalidate the signature.
  full,
}

/// Digitally Sign a document
class PdfSign extends PdfSignatureBase {
  /// Digitally Sign a document using RSA and SHA
  PdfSign.rsaSha1({
    required this.certificates,
    required Uint8List privateKey,
    this.name,
    this.location,
    this.reason,
    this.contactInfo,
    HashAlgorithm? digest,
    this.permissions,
  })  : assert(certificates.isNotEmpty),
        _reservedSpaceContents = 522,
        _signer = PdfRSASigner(
          privateKey: privateKey,
          digest: digest ?? HashAlgorithm.sha256,
        );

  /// Digitally Sign a document using an external pkcs7 signature
  PdfSign.pkcs7(
    PdfPkcs7Signer signer, {
    this.name,
    this.location,
    this.reason,
    this.contactInfo,
    this.permissions,
    int reservedSpace = 10000,
  })  : certificates = const <Uint8List>[],
        _reservedSpaceContents = reservedSpace * 2,
        _signer = signer;

  /// Digitally Sign a document using a pkcs7 RSA signature
  PdfSign.pkcs7Rsa({
    required X509 issuer,
    required List<X509> chain,
    required Uint8List privateKey,
    this.name,
    this.location,
    this.reason,
    this.contactInfo,
    HashAlgorithm? digest,
    this.permissions,
    int reservedSpace = 10000,
    TimestampSignCallback? onTimestampSign,
  })  : certificates = const <Uint8List>[],
        _reservedSpaceContents = reservedSpace * 2,
        _signer = PdfPkcs7RsaSigner(
          privateKey: privateKey,
          digest: digest ?? HashAlgorithm.sha1,
          chain: chain,
          issuer: issuer,
          onTimestampSign: onTimestampSign,
        );

  /// Reserved space for the /ByteRange parameter.
  static const int _reservedSpaceRange = 32;

  /// Reserved space for the /Content parameter.
  final int _reservedSpaceContents;

  final PdfSigner _signer;

  /// The certificate chain used to validate the document
  final List<Uint8List> certificates;

  int? _rangeOffset;

  int? _contentsOffset;

  /// Name of the person or authority signing the document
  final String? name;

  /// The machine name or physical location of the signing
  final String? location;

  /// The reason for the signing, such as (I agree...)
  final String? reason;

  /// Information provided by the signer to enable a recipient
  /// to contact the signer to verify the signature
  final String? contactInfo;

  /// Document permissions
  final PdfSignPerms? permissions;

  @override
  bool get hasMDP => permissions != null;

  @override
  void preSign(PdfObject object, PdfDict params) {
    params['/ByteRange'] =
        _PdfPrefill(_reservedSpaceRange, (o) => _rangeOffset ??= o);

    params['/Contents'] =
        _PdfPrefill(_reservedSpaceContents, (o) => _contentsOffset ??= o);

    params['/Filter'] = const PdfName('/Adobe.PPKLite');
    params['/SubFilter'] = PdfName(_signer.subFilter);

    params['/M'] = PdfString.fromDate(DateTime.now());

    if (name != null) {
      params['/Name'] = PdfString.fromString(name!);
    }

    if (location != null) {
      params['/Location'] = PdfString.fromString(location!);
    }

    if (reason != null) {
      params['/Reason'] = PdfString.fromString(reason!);
    }

    if (contactInfo != null) {
      params['/ContactInfo'] = PdfString.fromString(contactInfo!);
    }

    params['/Prop_Build'] = PdfDict({
      '/App': PdfDict({
        '/Name': const PdfName('/dart_pdf_crypto'),
      }),
    });

    if (certificates.length == 1) {
      params['/Cert'] =
          PdfString(certificates.first, format: PdfStringFormat.literal);
    } else if (certificates.isNotEmpty) {
      params['/Cert'] = PdfArray(
        certificates.map<PdfString>(
          (Uint8List cert) => PdfString(cert, format: PdfStringFormat.literal),
        ),
      );
    }

    if (permissions != null) {
      params['/Reference'] = PdfArray([
        PdfDict({
          '/TransformMethod': const PdfName('/DocMDP'),
          '/TransformParams': PdfDict({
            '/P': PdfNum(permissions!.index + 1),
          }),
        })
      ]);
    }

    // Calculate the final offsets
    final data = PdfStream();
    params.output(object, data, object.settings.verbose ? 0 : null);
  }

  @override
  Future<void> sign(PdfObject object, PdfStream os, PdfDict params,
      int? offsetStart, int? offsetEnd) async {
    final newRange = <int>[
      0,
      offsetStart! + _contentsOffset!,
      offsetStart + _contentsOffset! + _reservedSpaceContents,
      os.offset - (offsetStart + _contentsOffset! + _reservedSpaceContents),
    ];

    final rangeStream = PdfStream();
    PdfArray.fromNum(newRange).output(object, rangeStream);
    os.setBytes(
      offsetStart + _rangeOffset!,
      rangeStream.output(),
    );

    final uintOutput = os.output();

    final range = Iterable<PdfSignRange>.generate(
      newRange.length ~/ 2,
      (i) => PdfSignRange(
        newRange[i * 2],
        newRange[i * 2 + 1],
      ),
    );
    final signatureEncoded = await _signer.sign(uintOutput, range);
    if (_reservedSpaceContents ~/ 2 < signatureEncoded.lengthInBytes + 1) {
      throw Exception(
          'Not enough space to store the signature. Increase reservedSpace to more than ${signatureEncoded.lengthInBytes + 1}');
    }

    final fullSignature = Uint8List(_reservedSpaceContents ~/ 2 - 1);
    fullSignature.setAll(0, signatureEncoded);
    final contents = PdfStream();
    PdfString(fullSignature, format: PdfStringFormat.binary, encrypted: false)
        .output(object, contents);

    os.setBytes(
      offsetStart + _contentsOffset!,
      contents.output(),
    );
  }

  /// Convert a PEM x509 certificate to BER
  static Uint8List? pemCertificate(String cert) {
    return Uint8List.fromList(PemCodec(PemLabel.certificate).decode(cert));
  }

  /// Convert a PEM private key to BER
  static Uint8List? pemPrivateKey(String privateKey) {
    final keyData = PemCodec(
      PemLabel.privateKey,
    ).decode(privateKey);

    final asn1 = ASN1Parser(Uint8List.fromList(keyData));

    final seq = asn1.nextObject() as ASN1Sequence;

    final algorithm = seq.elements![1] as ASN1Sequence;

    final algoIod = algorithm.elements![0] as ASN1ObjectIdentifier;

    final data = seq.elements![2] as ASN1OctetString;

    if (algoIod.objectIdentifierAsString != '1.2.840.113549.1.1.1') {
      throw Exception(
          'Unknown private key type ${algoIod.objectIdentifierAsString}. Only Pkcs1 RSA is allowed');
    }

    return data.octets;
  }
}

class _PdfPrefill extends PdfDataType {
  const _PdfPrefill(
    this.length,
    this.setOffset,
  );

  final int length;

  final void Function(int offset) setOffset;

  @override
  void output(PdfObjectBase o, PdfStream s, [int? indent]) {
    setOffset(s.offset);
    s.putBytes(List<int>.filled(length, 0x20));
  }
}
