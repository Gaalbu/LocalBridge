import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/transfer.dart';

class IncomingTransferManager extends ChangeNotifier {
  final List<_PendingTransfer> _pending = [];
  final Map<String, Timer> _timers = {};

  List<IncomingTransferRequest> get pendingRequests =>
      List.unmodifiable(_pending.map((item) => item.request));

  Future<TransferDecision> enqueue(IncomingTransferRequest request) {
    final completer = Completer<TransferDecision>();
    _pending.add(_PendingTransfer(request, completer));
    _timers[request.requestId] = Timer(AppConstants.approvalTimeout, () {
      final expired = _take(request.requestId);
      if (expired != null && !expired.completer.isCompleted) {
        expired.completer.complete(
          const TransferDecision.reject('approval_timeout'),
        );
      }
    });
    notifyListeners();
    return completer.future;
  }

  void accept(String requestId) {
    final item = _take(requestId);
    if (item == null) return;
    item.completer.complete(
      TransferDecision.accept(item.request.files.map((file) => file.fileId)),
    );
  }

  void reject(String requestId) {
    final item = _take(requestId);
    if (item == null) return;
    item.completer.complete(const TransferDecision.reject());
  }

  _PendingTransfer? _take(String requestId) {
    final index = _pending.indexWhere(
      (item) => item.request.requestId == requestId,
    );
    if (index < 0) return null;
    final item = _pending.removeAt(index);
    _timers.remove(requestId)?.cancel();
    notifyListeners();
    return item;
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final item in _pending) {
      if (!item.completer.isCompleted) {
        item.completer.complete(const TransferDecision.reject('app_closed'));
      }
    }
    _pending.clear();
    super.dispose();
  }
}

class _PendingTransfer {
  const _PendingTransfer(this.request, this.completer);

  final IncomingTransferRequest request;
  final Completer<TransferDecision> completer;
}
