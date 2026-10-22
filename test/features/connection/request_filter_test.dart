import 'package:fl_clash/features/connection/request_filter.dart';
import 'package:fl_clash/features/connection/request_routing_actions.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _request({
  List<String> chains = const [],
  String process = 'browser',
  String host = 'Example.COM.',
}) => TrackerInfo(
  id: 'request',
  start: DateTime.utc(2026),
  metadata: Metadata(host: host, process: process),
  chains: chains,
  rule: '',
  rulePayload: '',
);

void main() {
  test('direct and rejected filters use the actual exit, not a group name', () {
    const direct = RequestFilter(disposition: RequestDisposition.direct);
    const rejected = RequestFilter(disposition: RequestDisposition.rejected);
    expect(direct.matches(_request(chains: ['DIRECT', 'Proxy'])), isTrue);
    expect(direct.matches(_request(chains: ['Tokyo', 'DIRECT'])), isFalse);
    expect(rejected.matches(_request(chains: ['REJECT'])), isTrue);
    expect(
      rejected.matches(_request(chains: ['REJECT-DROP', 'Proxy'])),
      isTrue,
    );
    expect(rejected.matches(_request()), isFalse);
  });

  test('process and exit filters compose without matching partial names', () {
    const filter = RequestFilter(process: 'browser', outbound: 'Tokyo');
    expect(filter.matches(_request(chains: ['Tokyo', 'Proxy'])), isTrue);
    expect(filter.matches(_request(chains: ['Tokyo 2', 'Proxy'])), isFalse);
    expect(
      filter.matches(_request(chains: ['Tokyo'], process: 'browser-helper')),
      isFalse,
    );
  });

  test(
    'rule creation uses only a recorded domain and rejects IP-only records',
    () {
      expect(requestDomain(_request()), 'example.com');
      for (final host in [
        '',
        '1.1.1.1',
        '::1',
        'example.com/path',
        'bad host',
      ]) {
        expect(requestDomain(_request(host: host)), isNull);
      }
    },
  );
}
