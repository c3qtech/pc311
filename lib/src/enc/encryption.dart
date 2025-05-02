/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import 'access_flags.dart';

const List<int> _padding = <int>[
  0x28,
  0xBF,
  0x4E,
  0x5E,
  0x4E,
  0x75,
  0x8A,
  0x41,
  0x64,
  0x00,
  0x4E,
  0x56,
  0xFF,
  0xFA,
  0x01,
  0x08,
  0x2E,
  0x2E,
  0x00,
  0xB6,
  0xD0,
  0x68,
  0x3E,
  0x80,
  0x2F,
  0x0C,
  0xA9,
  0xFE,
  0x64,
  0x53,
  0x69,
  0x7A
];

List<int> poValue(List<int> userKey, List<int> ownerKey, int length) {
  var key = crypto.md5.convert(ownerKey).bytes;

  if (length > 40) {
    for (var i = 0; i < 50; ++i) {
      key = crypto.md5.convert(key).bytes;
    }
  }

  key = key.sublist(0, length ~/ 8);
  var enc = rc4(userKey, key);

  if (length > 40) {
    for (var i = 1; i <= 19; ++i) {
      final ek = <int>[];
      for (var j = 0; j < key.length; ++j) {
        ek.add(key[j] ^ i);
      }
      enc = rc4(enc, ek);
    }
  }

  return enc;
}

List<int> puValue(List<int> encryptionKey, List<int> documentID, int length) {
  List<int> uValue;
  if (length <= 40) {
    uValue = rc4(_padding, encryptionKey);
  } else {
    final tmp = crypto.md5.convert(_padding + documentID).bytes;
    var enc = rc4(tmp, encryptionKey);

    for (var i = 1; i <= 19; ++i) {
      final ek = <int>[];
      for (var j = 0; j < encryptionKey.length; ++j) {
        ek.add(encryptionKey[j] ^ i);
      }
      enc = rc4(enc, ek);
    }
    enc.addAll(List<int>.filled(16, 0));
    uValue = enc.sublist(0, 32);
  }
  return uValue;
}

List<int> pEncryptionKey(List<int> userKey, List<int> documentID, int perm,
    List<int> oValue, int length) {
  final ps = protectionString(perm);
  var _key = crypto.md5
      .convert(userKey + oValue + ps + documentID)
      .bytes
      .sublist(0, length ~/ 8);

  if (length > 40) {
    for (var i = 0; i < 50; ++i) {
      _key = crypto.md5.convert(_key).bytes.sublist(0, length ~/ 8);
    }
  }
  return _key;
}

List<int>? password(String? password) {
  if (password == null) {
    return null;
  }

  return latin1.encode(password);
}

List<int>? passwordAesV3(String? password) {
  if (password == null) {
    return null;
  }

  return utf8.encode(password);
}

int permissions(Set<PdfAccessFlags>? accessFlags) {
  if (accessFlags == null) {
    return 0;
  }

  var permissions = 0;
  if (accessFlags.contains(PdfAccessFlags.Print)) {
    permissions |= 0x00000004; // bit 3
  }
  if (accessFlags.contains(PdfAccessFlags.Modify)) {
    permissions |= 0x00000008; // bit 4
  }
  if (accessFlags.contains(PdfAccessFlags.Copy)) {
    permissions |= 0x00000010; // bit 5
  }
  if (accessFlags.contains(PdfAccessFlags.Annotate)) {
    permissions |= 0x00000020; // bit 6
  }
  if (accessFlags.contains(PdfAccessFlags.Interactive)) {
    permissions |= 0x00000100; // bit 9
  }
  if (accessFlags.contains(PdfAccessFlags.Accessibility)) {
    permissions |= 0x00000200; // bit 10
  }
  if (accessFlags.contains(PdfAccessFlags.Assemble)) {
    permissions |= 0x00000400; // bit 11
  }
  if (accessFlags.contains(PdfAccessFlags.HighQualityPrint)) {
    permissions |= 0x00000804; // bit 12
  }
  return permissions;
}

List<int> paddedKey(List<int> password) {
  final result = <int>[];
  result.addAll(password);
  result.addAll(_padding);
  return result.sublist(0, 32);
}

List<int> rc4(List<int> message, List<int> key) {
  var _i = 0;
  var _j = 0;
  var x = 0;
  final box = List<int>.generate(256, (int i) => i);
  for (var i = 0; i < 256; i++) {
    x = (x + box[i] + key[i % key.length]) % 256;
    final tmp = box[i];
    box[i] = box[x];
    box[x] = tmp;
  }

  final out = <int>[];

  for (var char in message) {
    _i = (_i + 1) % 256;
    _j = (_j + box[_i]) % 256;
    final tmp = box[_i];
    box[_i] = box[_j];
    box[_j] = tmp;

    final c = char ^ (box[(box[_i] + box[_j]) % 256]);
    out.add(c);
  }
  return out;
}

List<int> protectionString(int protection) {
  final result = <int>[];
  result.add(protection & 0xff);
  result.add((protection & 0xff00) >> 8);
  result.add((protection & 0xff0000) >> 16);
  result.add((protection & 0xff000000) >> 24);
  return result;
}

List<int> randomBytes(int length) {
  final rnd = math.Random.secure();
  return List<int>.generate(length, (_) => rnd.nextInt(256));
}
