/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

import '../pdf.dart';
import 'access_flags.dart';
import 'encryption.dart';

/// RC4 encryption level
enum PdfRC4Level {
  /// 40 bits RC4 encryption
  low,

  /// 128 bits RC4 encryption
  high,
}

/// Encrypt the document using RC4
class PdfEncryptionRC4 extends PdfEncryption {
  /// Creates a [PdfEncryptionRC4] object to encrypt the entire document
  factory PdfEncryptionRC4(
    PdfDocument pdfDocument, {
    String? user,
    String? owner,
    Set<PdfAccessFlags>? accessFlags,
    PdfRC4Level? level,
  }) {
    final _owner = password(owner) ?? randomBytes(32);
    final length = level == PdfRC4Level.low ? 40 : 128;
    final userKey = paddedKey(password(user) ?? <int>[]);
    final ownerKey = paddedKey(_owner);
    final perm = permissions(accessFlags);

    final oValue = poValue(
      userKey,
      ownerKey,
      length,
    );

    final encryptionKey = pEncryptionKey(
      userKey,
      pdfDocument.documentID,
      perm,
      oValue,
      length,
    );

    return PdfEncryptionRC4.build(
      pdfDocument,
      puValue(
        encryptionKey,
        pdfDocument.documentID,
        length,
      ),
      oValue,
      encryptionKey,
      perm,
      length,
    );
  }

  @protected
  PdfEncryptionRC4.build(
    PdfDocument pdfDocument,
    List<int> uValue,
    List<int> oValue,
    this.encryptionKey,
    int accessFlags,
    this.length,
  ) : super(pdfDocument) {
    params['/Filter'] = const PdfName('/Standard');
    params['/V'] = PdfNum(length > 40 ? 2 : 1);
    params['/Length'] = PdfNum(length);
    params['/R'] = PdfNum(length > 40 ? 3 : 2);
    params['/O'] = PdfString(Uint8List.fromList(oValue), encrypted: false);
    params['/U'] = PdfString(Uint8List.fromList(uValue), encrypted: false);
    params['/P'] = PdfNum(accessFlags);
  }

  /// the key length: 40 or 128 bytes
  final int length;

  /// The encryption key
  final List<int> encryptionKey;

  @protected
  List<int> keyHash(int objser, int objgen) {
    final localKey = <int>[];
    localKey.addAll(encryptionKey);
    localKey.add(objser & 0xff);
    localKey.add((objser & 0xff00) >> 8);
    localKey.add((objser & 0xff0000) >> 16);
    localKey.add(objgen & 0xff);
    localKey.add((objgen & 0xff00) >> 8);

    return crypto.md5.convert(localKey).bytes.sublist(
          0,
          math.min(length ~/ 8 + 5, 16),
        );
  }

  @override
  Uint8List encrypt(Uint8List input, PdfObjectBase object) {
    final hash = keyHash(object.objser, object.objgen);
    return Uint8List.fromList(rc4(input, hash));
  }
}
