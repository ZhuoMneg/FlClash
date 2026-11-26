import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';

NetworkTunnelSettings parseNetworkTunnelImport(String text, int profileId) {
  if (text.length > 65536) throw const FormatException('Invalid tunnel config');
  final data = jsonDecode(text);
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Invalid tunnel config');
  }
  final value = NetworkTunnelSettings.fromJson(data);
  bool address(String text, InternetAddressType type) {
    final ip = InternetAddress.tryParse(text);
    if (ip == null || ip.type != type || ip.isLoopback || ip.isLinkLocal) {
      return false;
    }
    final bytes = ip.rawAddress;
    if (type == InternetAddressType.IPv4) {
      return bytes.any((v) => v != 0) &&
          !bytes.every((v) => v == 255) &&
          !(bytes[0] >= 224 && bytes[0] <= 239);
    }
    return bytes.any((v) => v != 0) && bytes[0] != 255;
  }

  bool publicHost(String text) {
    if (!address(text, InternetAddressType.IPv4)) return false;
    final bytes = InternetAddress(text).rawAddress;
    return bytes[0] != 0 &&
        bytes[0] != 10 &&
        !(bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) &&
        !(bytes[0] == 192 && bytes[1] == 168) &&
        !(bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) &&
        !(bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19));
  }

  bool key(String text) {
    try {
      return RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(text) &&
          base64Decode(text).length == 32;
    } on FormatException {
      return false;
    }
  }

  if (!publicHost(value.host) ||
      value.port < 1 ||
      value.port > 65535 ||
      !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value.pin) ||
      value.token.length < 40 ||
      value.token.length > 512 ||
      value.token.contains(RegExp(r'[\r\n]')) ||
      !key(value.privateKey) ||
      !key(value.publicKey) ||
      !address(value.ip, InternetAddressType.IPv4) ||
      !address(value.dns, InternetAddressType.IPv4) ||
      (value.ipv6.isNotEmpty &&
          !address(value.ipv6, InternetAddressType.IPv6))) {
    throw const FormatException('Invalid tunnel config');
  }
  return value.copyWith(profileId: profileId, enabled: true, extension: true);
}
