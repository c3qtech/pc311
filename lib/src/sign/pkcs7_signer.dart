/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import 'package:pkcs7/pkcs7.dart';

import 'signer.dart';

/// Digitally Sign a document using Pkcs7
abstract class PdfPkcs7Signer extends PdfSigner {
  /// Create a Pkcs7 signer
  const PdfPkcs7Signer();

  @override
  String get subFilter => '/adbe.pkcs7.detached';
}

/// Timestamp request callback
///
/// Example using dart:io
/// ```dart
/// final url = Uri.parse('http://ts.ssl.com');
/// final client = HttpClient();
/// final request = await client.postUrl(url);
/// request.headers.contentType =
///     ContentType('application', 'timestamp-query');
/// request.contentLength = tsq.lengthInBytes;
/// request.add(tsq);
/// final response = await request.close();
/// final tsr =
///     await response.reduce((previous, element) => previous + element);
/// if (response.statusCode != 200) {
///   throw Exception(utf8.decode(tsr));
/// }
/// return Uint8List.fromList(tsr);
/// ```
typedef TimestampSignCallback = Future<Uint8List?> Function(Uint8List tsq);

/// Digitally Sign a document using Pkcs7 and RSA
class PdfPkcs7RsaSigner extends PdfPkcs7Signer {
  /// Create a Pkcs7 RSA signer
  const PdfPkcs7RsaSigner({
    required this.privateKey,
    required this.digest,
    this.chain = const <X509>[],
    required this.issuer,
    this.onTimestampSign,
  });

  /// The private key used to digitally sign the document
  final Uint8List privateKey;

  /// The hash algorithm used to validate the document authenticity
  final HashAlgorithm digest;

  /// Certification chain. It is intended that the set be sufficient to
  /// contain chains from a recognized "root" or "top-level certification
  /// authority" to all of the signers in the signerInfos field
  final List<X509> chain;

  /// specifies the signer's certificate (and thereby the signer's
  /// distinguished name and public key) by issuer distinguished name
  /// and issuer-specific serial number.
  final X509 issuer;

  /// Called to counter-sign the message with an authenticated timestamp
  final TimestampSignCallback? onTimestampSign;

  @override
  Future<Uint8List> sign(Uint8List input, Iterable<PdfSignRange> range) async {
    final hash = createDigest(digest, input, range);
    final builder = Pkcs7Builder();
    builder.addCertificate(issuer);
    chain.forEach(builder.addCertificate);
    final signerInfo = Pkcs7SignerInfoBuilder.rsa(
      issuer: issuer,
      privateKey: loadRSAPrivateKey(privateKey),
      digestAlgorithm: digest,
    );
    signerInfo.addSMimeDigest(digest: hash);

    // Timestamp counter-signature
    if (onTimestampSign != null) {
      final tsq = signerInfo.generateTSQ();
      final tsr = await onTimestampSign!(tsq);
      if (tsr != null) {
        signerInfo.addTimestamp(tsr: TimestampResponse.fromDer(tsr));
      }
    }

    builder.addSignerInfo(signerInfo);

    final pkcs7 = builder.build();
    return pkcs7.der;
  }
}
