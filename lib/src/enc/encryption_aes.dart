/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import '../pdf.dart';
import 'access_flags.dart';
import 'encryption.dart';
import 'encryption_rc4.dart';

/// AES Encryption level
enum PdfAESLevel {
  /// AES 128 encryption
  low,

  /// AES 256 encryption
  high,
}

/// Encrypt the PDF Using AES
class PdfEncryptionAES extends PdfEncryptionRC4 {
  /// Create a [PdfEncryptionAES] object to encrypt the entire document
  factory PdfEncryptionAES(
    PdfDocument pdfDocument, {
    String? user,
    String? owner,
    Set<PdfAccessFlags>? accessFlags,
    PdfAESLevel? level,
  }) {
    if (level == PdfAESLevel.low) {
      final _owner = password(owner) ?? randomBytes(32);
      const length = 128;
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

      return PdfEncryptionAES._aesV2(
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

    const length = 256;
    final userKey = passwordAesV3(user) ?? <int>[];
    final ownerKey = passwordAesV3(owner) ?? randomBytes(32);

    final perm = permissions(accessFlags);

    final encryptionKey =
        crypto.sha256.convert(randomBytes(512)).bytes.sublist(0, length ~/ 8);

    final userSeed = crypto.sha256.convert(randomBytes(512)).bytes;
    final userValidationSalt = userSeed.sublist(0, 8);
    final userKeySalt = userSeed.sublist(8, 16);

    final uValue = <int>[
      ...crypto.sha256.convert(<int>[...userKey, ...userValidationSalt]).bytes,
      ...userValidationSalt,
      ...userKeySalt
    ];

    final userHash =
        crypto.sha256.convert(<int>[...userKey, ...userKeySalt]).bytes;

    final ueValue = _aesNoPadding(
        Uint8List.fromList(userHash), Uint8List.fromList(encryptionKey));

    final ownerSeed = crypto.sha256.convert(randomBytes(512)).bytes;
    final ownerValidationSalt = ownerSeed.sublist(0, 8);
    final ownerKeySalt = ownerSeed.sublist(8, 16);
    final oValue = <int>[
      ...crypto.sha256
          .convert(<int>[...ownerKey, ...ownerValidationSalt, ...uValue]).bytes,
      ...ownerValidationSalt,
      ...ownerKeySalt
    ];

    final ownerHash = crypto.sha256
        .convert(<int>[...ownerKey, ...ownerKeySalt, ...uValue]).bytes;

    final oeValue = _aesNoPadding(
        Uint8List.fromList(ownerHash), Uint8List.fromList(encryptionKey));

    return PdfEncryptionAES._aesV3(
      pdfDocument,
      uValue,
      ueValue,
      oValue,
      oeValue,
      encryptionKey,
      perm,
      length,
    );
  }

  PdfEncryptionAES._aesV2(
    PdfDocument pdfDocument,
    List<int> uValue,
    List<int> oValue,
    List<int> encryptionKey,
    int accessFlags,
    int length,
  ) : super.build(
          pdfDocument,
          uValue,
          oValue,
          encryptionKey,
          accessFlags,
          length,
        ) {
    params['/CF'] = PdfDict(<String, PdfDataType>{
      '/StdCF': PdfDict(<String, PdfDataType>{
        '/Type': const PdfName('/CryptFilter'),
        '/CFM': const PdfName('/AESV2'),
        '/AuthEvent': const PdfName('/DocOpen'),
        '/Length': PdfNum(length),
      }),
    });
    params['/StmF'] = const PdfName('/StdCF');
    params['/StrF'] = const PdfName('/StdCF');
    params['/V'] = const PdfNum(4);
    params['/R'] = const PdfNum(4);
  }

  PdfEncryptionAES._aesV3(
    PdfDocument pdfDocument,
    List<int> uValue,
    List<int> ueValue,
    List<int> oValue,
    List<int> oeValue,
    List<int> encryptionKey,
    int accessFlags,
    int length,
  ) : super.build(
          pdfDocument,
          uValue,
          oValue,
          encryptionKey,
          accessFlags,
          length,
        ) {
    params['/CF'] = PdfDict(<String, PdfDataType>{
      '/StdCF': PdfDict(<String, PdfDataType>{
        '/Type': const PdfName('/CryptFilter'),
        '/CFM': const PdfName('/AESV3'),
        '/AuthEvent': const PdfName('/DocOpen'),
        '/Length': PdfNum(length),
      }),
    });

    final List<int> perms = _aesNoPadding(
      Uint8List.fromList(encryptionKey),
      Uint8List.fromList(
        protectionString(accessFlags) +
            <int>[
              0xff,
              0xff,
              0xff,
              0xff,
              if (encryptMetadata) 0x54 else 0x46,
              0x61,
              0x64,
              0x62,
              0x6e,
              0x69,
              0x63,
              0x6b
            ],
      ),
    );

    params['/Perms'] = PdfString(Uint8List.fromList(perms), encrypted: false);
    params['/StmF'] = const PdfName('/StdCF');
    params['/StrF'] = const PdfName('/StdCF');
    params['/V'] = const PdfNum(5);
    params['/R'] = const PdfNum(5);
    params['/OE'] = PdfString(Uint8List.fromList(oeValue), encrypted: false);
    params['/UE'] = PdfString(Uint8List.fromList(ueValue), encrypted: false);
    params['/EncryptMetadata'] = const PdfBool(encryptMetadata);
  }

  /// Wether to encrypt PDF metadata or not
  static const bool encryptMetadata = true;

  @override
  Uint8List keyHash(int objser, int objgen) {
    final localKey = <int>[];
    localKey.addAll(encryptionKey);
    localKey.add(objser & 0xff);
    localKey.add((objser & 0xff00) >> 8);
    localKey.add((objser & 0xff0000) >> 16);
    localKey.add(objgen & 0xff);
    localKey.add((objgen & 0xff00) >> 8);
    localKey.addAll(<int>[0x73, 0x41, 0x6c, 0x54]);

    return Uint8List.fromList(crypto.md5.convert(localKey).bytes.sublist(
          0,
          math.min(length ~/ 8 + 5, 16),
        ));
  }

  @override
  Uint8List encrypt(Uint8List input, PdfObjectBase object) {
    final hash =
        length <= 128 ? keyHash(object.objser, object.objgen) : encryptionKey;

    final iv = randomBytes(16);
    final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..reset()
      ..init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(
              KeyParameter(Uint8List.fromList(hash)), Uint8List.fromList(iv)),
          null,
        ),
      );

    final output = cipher.process(input);
    return Uint8List.fromList(iv + output);
  }
}

Uint8List _aesNoPadding(Uint8List key, Uint8List input) {
  final cipher = CBCBlockCipher(AESEngine())
    ..reset()
    ..init(
      true,
      ParametersWithIV<KeyParameter>(
        KeyParameter(key),
        Uint8List.fromList(List<int>.filled(16, 0)),
      ),
    );

  final output = Uint8List(input.length);

  for (var offset = 0; offset < input.length;) {
    offset += cipher.processBlock(input, offset, output, offset);
  }

  return output;
}
