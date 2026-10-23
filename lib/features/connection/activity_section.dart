import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

class NetworkActivitySection extends InheritedWidget {
  const NetworkActivitySection({
    super.key,
    required this.tabs,
    required super.child,
  });

  final Widget tabs;

  static NetworkActivitySection? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NetworkActivitySection>();

  static String? titleOf(BuildContext context) =>
      _of(context) == null ? null : context.appLocalizations.networkActivity;

  static Widget wrap(BuildContext context, Widget child) {
    final scope = _of(context);
    if (scope == null) return child;
    return Column(
      children: [
        AppBarClearance(child: scope.tabs),
        Expanded(
          child: FloatingBarScope(
            inset: 0,
            child: TopInsetScope(inset: 8, child: child),
          ),
        ),
      ],
    );
  }

  @override
  bool updateShouldNotify(NetworkActivitySection oldWidget) =>
      tabs != oldWidget.tabs;
}
