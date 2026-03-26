import 'package:flutter/foundation.dart';

import '../../data/datasources/auto_reply_service.dart';

class AutoReplyViewModel extends ChangeNotifier {
  AutoReplyViewModel({required AutoReplyService autoReplyService})
    : _service = autoReplyService {
    _service.onStateChanged = _onServiceChanged;
    _service.startMonitoring();
  }

  final AutoReplyService _service;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  int get repliedCount => _service.repliedCount;
  int get queueCount => _service.queueCount;

  void toggle() {
    _isEnabled = !_isEnabled;

    if (_isEnabled) {
      _service.start();
    } else {
      _service.stop();
    }

    notifyListeners();
  }

  void enable() {
    if (_isEnabled) {
      return;
    }

    _isEnabled = true;
    _service.start();
    notifyListeners();
  }

  void disable() {
    if (!_isEnabled) {
      return;
    }

    _isEnabled = false;
    _service.stop();
    notifyListeners();
  }

  void setBulkSendingActive(bool active) {
    _service.setBulkSendingActive(active);
  }

  void markAsManuallyAnswered(String phone) {
    _service.markAsManuallyAnswered(phone);
    notifyListeners();
  }

  Future<int> syncRecentConversations({DateTime? visibleFrom}) {
    return _service.syncRecentConversations(visibleFrom: visibleFrom);
  }

  Future<void> sendManualChatMessage({
    required String phone,
    String? sendTarget,
    required String text,
    String name = '',
  }) async {
    await _service.sendManualChatMessage(
      phone: phone,
      sendTarget: sendTarget,
      text: text,
      name: name,
    );
    notifyListeners();
  }

  void _onServiceChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _service.onStateChanged = null;
    _service.stop();
    _service.stopMonitoring();
    super.dispose();
  }
}
