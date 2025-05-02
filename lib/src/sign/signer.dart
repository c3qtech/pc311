/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pkcs7/pkcs7.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// PDF Signature range
class PdfSignRange {
  /// Create a PDF Signature range
  const PdfSignRange(
    this.start,
    this.length,
  ) : assert(length >= 0);

  /// Start range
  final int start;

  /// Length of the range
  final int length;

  /// End range
  int get end => start + length;
}

/// Digitally Sign a document
abstract class PdfSigner with Pkcs {
  /// Create a digital signature
  const PdfSigner();

  /// Pdf SubFilter name
  String get subFilter;

  /// Create a hash of the message
  @protected
  Uint8List createDigest(
      HashAlgorithm algorithm, Uint8List input, Iterable<PdfSignRange> range) {
    final digest = getDigest(algorithm);
    final hash = Uint8List(digest.digestSize);

    digest.reset();
    for (final r in range) {
      digest.update(input, r.start, r.length);
    }
    digest.doFinal(hash, 0);

    return hash;
  }

  /// Parse BER encoded RSA key pair
  @protected
  RSAPrivateKey loadRSAPrivateKey(Uint8List keyData) {
    final asn1 = ASN1Parser(keyData);
    final seq = asn1.nextObject() as ASN1Sequence;
    final modulus = seq.elements![1] as ASN1Integer;
    final privateExponent = seq.elements![3] as ASN1Integer;
    final prime1 = seq.elements![4] as ASN1Integer;
    final prime2 = seq.elements![5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.integer!,
      privateExponent.integer!,
      prime1.integer,
      prime2.integer,
    );
  }

  /// Sign the data and return the signature
  Future<Uint8List> sign(Uint8List input, Iterable<PdfSignRange> range);
}
