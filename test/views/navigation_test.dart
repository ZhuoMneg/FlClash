import 'package:fl_clash/views/navigation.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/common/common.dart' show system;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request history is directly available in the desktop navigation', () {
    final items = navigation.getItems(hasProxies: true, openLogs: true);
    final desktop = items
        .where((item) => item.modes.contains(NavigationItemMode.desktop))
        .map((item) => item.label)
        .toList();

    expect(desktop, [
      PageLabel.dashboard,
      PageLabel.proxies,
      PageLabel.profiles,
      PageLabel.routing,
      PageLabel.requests,
      PageLabel.tools,
      if (system.isWindows) PageLabel.networkTunnel,
      PageLabel.settings,
    ]);
  });

  test('active connections remain available through tools', () {
    final connections = navigation.getItems().singleWhere(
      (item) => item.label == PageLabel.connections,
    );

    expect(connections.modes, contains(NavigationItemMode.moreFull));
    expect(connections.modes, isNot(contains(NavigationItemMode.desktop)));
  });

  testWidgets('no navigation view carries a global key of its own', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    );

    final items = navigation.getItems(openLogs: true, hasProxies: true);

    for (final item in items) {
      expect(item.builder(context).key, isNot(isA<GlobalKey>()));
    }
  });
}
