import 'dart:async';

import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class SettingSearchDestination extends StatefulWidget {
  const SettingSearchDestination({
    super.key,
    required this.target,
    required this.child,
  });

  final String target;
  final Widget child;

  @override
  State<SettingSearchDestination> createState() =>
      _SettingSearchDestinationState();
}

class _SettingSearchDestinationState extends State<SettingSearchDestination> {
  final _content = GlobalKey();
  Rect? _highlight;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reveal()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Element? _findTarget() {
    Element? match;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data == this.widget.target) {
        match = element;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is ListItem) {
            match = ancestor;
            return false;
          }
          return ancestor != _content.currentContext;
        });
      }
      if (match == null) element.visitChildren(visit);
    }

    (_content.currentContext as Element?)?.visitChildren(visit);
    return match;
  }

  ScrollableState? _scrollable() {
    ScrollableState? result;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (axisDirectionToAxis(state.position.axisDirection) ==
            Axis.vertical) {
          result ??= state;
        }
      }
      element.visitChildren(visit);
    }

    (_content.currentContext as Element?)?.visitChildren(visit);
    return result;
  }

  Future<void> _reveal() async {
    for (var attempt = 0; mounted && attempt < 40; attempt++) {
      final target = _findTarget();
      if (target != null) {
        await Scrollable.ensureVisible(target, alignment: 0.4);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !target.mounted) return;
        final box = target.findRenderObject();
        final content = _content.currentContext?.findRenderObject();
        if (box is RenderBox && content is RenderBox && box.hasSize) {
          setState(
            () => _highlight =
                content.globalToLocal(box.localToGlobal(Offset.zero)) &
                box.size,
          );
          _timer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _highlight = null);
          });
        }
        return;
      }
      final scrollable = _scrollable();
      if (scrollable == null) return;
      final position = scrollable.position;
      final next = (position.pixels + position.viewportDimension * 0.75).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next == position.pixels) return;
      position.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: _content,
    fit: StackFit.expand,
    children: [
      NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          if (_highlight != null) setState(() => _highlight = null);
          return false;
        },
        child: widget.child,
      ),
      if (_highlight case final rect?)
        Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('settings-search-highlight'),
              decoration: ShapeDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                shape: AppShape.lg.copyWith(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
