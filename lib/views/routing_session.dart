import 'dart:async';

import 'package:flutter/foundation.dart';

enum RoutingApplyState { ready, pending, applying, applied, failed }

class RoutingApplySession extends ChangeNotifier {
  RoutingApplySession({required this.isCurrent, required this.apply});

  final bool Function() isCurrent;
  final Future<bool> Function() apply;
  RoutingApplyState state = RoutingApplyState.ready;
  Timer? _timer;
  var _revision = 0;
  var _running = false;
  var _disposed = false;

  void changed() {
    if (_disposed || !isCurrent()) return;
    _revision++;
    _setState(RoutingApplyState.pending);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), applyNow);
  }

  Future<void> applyNow() async {
    _timer?.cancel();
    if (_disposed || _running || !isCurrent()) return;
    _running = true;
    final revision = _revision;
    _setState(RoutingApplyState.applying);
    try {
      final applied = await apply();
      if (!_disposed && isCurrent()) {
        _setState(
          applied ? RoutingApplyState.applied : RoutingApplyState.failed,
        );
      }
    } catch (_) {
      _setState(RoutingApplyState.failed);
    } finally {
      _running = false;
      if (!_disposed && revision != _revision && isCurrent()) {
        _setState(RoutingApplyState.pending);
        _timer = Timer(const Duration(milliseconds: 300), applyNow);
      }
    }
  }

  void _setState(RoutingApplyState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
