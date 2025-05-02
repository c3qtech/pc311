/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import 'package:pkcs7/pkcs7.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import 'signer.dart';

/// Digitally Sign a document using x509 certificates and RSA
class PdfRSASigner extends PdfSigner {
  /// Create an RSA signer
  const PdfRSASigner({required this.privateKey, required this.digest});

  /// The private key used to digitally sign the document
  final Uint8List privateKey;

  /// The hash algorithm used to validate the document authenticity
  final HashAlgorithm digest;

  @override
  String get subFilter => '/adbe.x509.rsa_sha1';

  @override
  Future<Uint8List> sign(Uint8List input, Iterable<PdfSignRange> range) async {
    final hash = createDigest(digest, input, range);
    final data = derEncode(hash, digest);

    final privKey = loadRSAPrivateKey(privateKey);
    final param = PrivateKeyParameter<RSAPrivateKey>(privKey);
    final rsa = PKCS1Encoding(RSAEngine());
    rsa.init(true, param);
    final signature = Uint8List(rsa.outputBlockSize);
    rsa.processBlock(data, 0, data.length, signature, 0);
    return ASN1OctetString(octets: signature).encode();
  }
}
