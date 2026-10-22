import 'package:fl_clash/models/models.dart';

enum RequestDisposition { any, direct, rejected }

class RequestFilter {
  const RequestFilter({
    this.disposition = RequestDisposition.any,
    this.process,
    this.outbound,
  });

  final RequestDisposition disposition;
  final String? process;
  final String? outbound;

  bool get isActive =>
      disposition != RequestDisposition.any ||
      process != null ||
      outbound != null;

  bool matches(TrackerInfo request) {
    final exit = request.chains.firstOrNull ?? '';
    final kind = exit.toUpperCase();
    if (disposition == RequestDisposition.direct && kind != 'DIRECT') {
      return false;
    }
    if (disposition == RequestDisposition.rejected &&
        kind != 'REJECT' &&
        kind != 'REJECT-DROP') {
      return false;
    }
    return (process == null || request.metadata.process == process) &&
        (outbound == null || exit == outbound);
  }
}
