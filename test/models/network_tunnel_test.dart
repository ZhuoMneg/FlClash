import 'dart:convert';

import 'package:fl_clash/common/network_tunnel.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> validConfig() => {
  'host': '179.253.249.97',
  'pin': 'a' * 64,
  'token': 't' * 48,
  'privateKey': base64Encode(List.filled(32, 1)),
  'publicKey': base64Encode(List.filled(32, 2)),
  'ip': '10.203.77.2',
  'ipv6': 'fd42:203:77::2',
  'dns': '10.203.77.1',
};

void main() {
  test('unconfigured settings never apply', () {
    const settings = NetworkTunnelSettings();
    expect(settings.appliesTo(null), isFalse);
    expect(settings.appliesTo(1), isFalse);
  });

  test('import binds to selected profile and enables switches', () {
    final settings = parseNetworkTunnelImport(
      jsonEncode({
        ...validConfig(),
        'profileId': 999,
        'enabled': false,
        'extension': false,
      }),
      42,
    );
    expect(settings.appliesTo(42), isTrue);
    expect(settings.appliesTo(999), isFalse);
    expect(settings.enabled && settings.extension, isTrue);
    expect(settings.toString(), isNot(contains(settings.privateKey)));
    expect(settings.toString(), isNot(contains(settings.token)));
    final disabled = settings.copyWith(enabled: false, extension: false);
    expect(NetworkTunnelSettings.fromJson(disabled.toJson()), disabled);
  });

  test('reject malformed imports without exposing their contents', () {
    for (final bad in [
      {'privateKey': 'invalid'},
      {'ipv6': '127.0.0.1'},
      {'port': 0},
      {'pin': 'no'},
      {'token': '${'x' * 48}\n'},
      {'dns': 'example.com'},
      {'ip': '127.0.0.1'},
      {'dns': '169.254.1.1'},
      {'ip': '0.0.0.0'},
      {'dns': '224.0.0.1'},
      {'ipv6': '::'},
      {'ipv6': '::1'},
      {'ipv6': 'fe80::1'},
      {'ipv6': 'ff02::1'},
      {'privateKey': base64Encode(List.filled(32, 1)).replaceAll('=', '')},
    ]) {
      expect(
        () =>
            parseNetworkTunnelImport(jsonEncode({...validConfig(), ...bad}), 1),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('reject directory addresses the core cannot use', () {
    for (final host in [
      '0.1.1.1',
      '10.0.0.1',
      '100.64.0.1',
      '100.127.255.254',
      '127.0.0.1',
      '169.254.1.1',
      '172.16.0.1',
      '192.168.6.1',
      '198.18.0.1',
      '198.19.255.254',
      '224.0.0.1',
      '255.255.255.255',
    ]) {
      expect(
        () => parseNetworkTunnelImport(
          jsonEncode({...validConfig(), 'host': host}),
          1,
        ),
        throwsA(isA<FormatException>()),
        reason: host,
      );
    }
    for (final host in ['100.63.255.254', '100.128.0.1', '172.32.0.1']) {
      expect(
        parseNetworkTunnelImport(
          jsonEncode({...validConfig(), 'host': host}),
          1,
        ).host,
        host,
      );
    }
  });
}
