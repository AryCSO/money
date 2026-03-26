import 'dart:io';
import 'dart:math' as math;

import 'evolution_api_service.dart';

class SendHistoryService {
  SendHistoryService({
    Directory? historyDirectory,
    EvolutionApiService? evolutionApiService,
    Duration? remoteCacheTtl,
  }) : _historyDirectory = historyDirectory ?? Directory(_defaultHistoryPath),
       _evolutionApiService = evolutionApiService,
       _remoteCacheTtl = remoteCacheTtl ?? const Duration(minutes: 5);

  static const int defaultLookbackDays = 30;
  static const String _defaultHistoryPath = r'C:\money';
  static const String _responsesFolderName = 'respostas';
  static const int _maxChatsToInspect = 200;
  static const int _maxMessagesPerChat = 60;
  static final RegExp _nonDigitsRegex = RegExp(r'\D');
  static final RegExp _lineBreakRegex = RegExp(r'[\r\n]+');

  final Directory _historyDirectory;
  final EvolutionApiService? _evolutionApiService;
  final Duration _remoteCacheTtl;
  Set<String>? _recentPhonesCache;
  String? _cacheKey;
  Set<String> _remoteSentPhonesCache = <String>{};
  DateTime? _remoteSnapshotAt;
  int? _remoteSnapshotLookbackDays;
  Future<void>? _remoteSyncFuture;

  Future<bool> wasSentInLastDays(
    String phone, {
    int days = defaultLookbackDays,
  }) async {
    final targetKeys = _buildPhoneMatchKeys(phone);
    if (targetKeys.isEmpty) {
      return false;
    }

    try {
      final recentPhones = await _loadRecentPhones(days: days);
      return _containsAny(recentPhones, targetKeys);
    } catch (_) {
      return false;
    }
  }

  Future<void> saveSuccessfulSend(String phone) async {
    final normalizedPhone = _normalizePhone(phone);
    final keysToRegister = _buildPhoneMatchKeys(normalizedPhone);
    if (normalizedPhone.isEmpty) {
      return;
    }

    try {
      await _ensureHistoryDirectoryExists();
      final todayFile = File(_dailyFilePath(DateTime.now()));
      final recentPhones = await _loadRecentPhones(days: defaultLookbackDays);

      if (_containsAny(recentPhones, keysToRegister)) {
        return;
      }

      await todayFile.writeAsString(
        '$normalizedPhone\n',
        mode: FileMode.append,
        flush: true,
      );
      recentPhones.addAll(keysToRegister);
    } catch (_) {
      // Falha de persistencia nao deve interromper o envio.
    }
  }

  Future<void> warmUpRemoteHistory() async {
    if (_evolutionApiService == null) {
      return;
    }

    try {
      await _syncRemoteHistoryIfNeeded(days: defaultLookbackDays);
    } catch (_) {
      // Se falhar, seguimos com a lista local sem interromper o fluxo.
    }
  }

  Future<bool> wasSentByEvolutionHistory(
    String phone, {
    int days = defaultLookbackDays,
  }) async {
    final targetKeys = _buildPhoneMatchKeys(phone);
    if (targetKeys.isEmpty || _evolutionApiService == null) {
      return false;
    }

    try {
      await _syncRemoteHistoryIfNeeded(days: days);
      return _containsAny(_remoteSentPhonesCache, targetKeys);
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> _loadRecentPhones({required int days}) async {
    final cacheKey = '${_formatDate(DateTime.now())}-$days';
    if (_recentPhonesCache != null && _cacheKey == cacheKey) {
      return _recentPhonesCache!;
    }

    final recentPhones = <String>{};

    if (!await _historyDirectory.exists()) {
      _recentPhonesCache = recentPhones;
      _cacheKey = cacheKey;
      return recentPhones;
    }

    final today = DateTime.now();
    for (var offset = 0; offset < days; offset++) {
      final date = today.subtract(Duration(days: offset));
      final file = File(_dailyFilePath(date));

      if (!await file.exists()) {
        continue;
      }

      final lines = await file.readAsLines();
      for (final line in lines) {
        final normalizedPhone = _normalizePhone(line);
        if (normalizedPhone.isNotEmpty) {
          recentPhones.addAll(_buildPhoneMatchKeys(normalizedPhone));
        }
      }
    }

    _recentPhonesCache = recentPhones;
    _cacheKey = cacheKey;
    return recentPhones;
  }

  Future<void> _ensureHistoryDirectoryExists() async {
    if (!await _historyDirectory.exists()) {
      await _historyDirectory.create(recursive: true);
    }
  }

  Future<void> _syncRemoteHistoryIfNeeded({required int days}) async {
    if (_evolutionApiService == null) {
      return;
    }

    final now = DateTime.now();
    final hasFreshSnapshot =
        _remoteSnapshotLookbackDays == days &&
        _remoteSnapshotAt != null &&
        now.difference(_remoteSnapshotAt!) <= _remoteCacheTtl;
    if (hasFreshSnapshot) {
      return;
    }

    if (_remoteSyncFuture != null) {
      await _remoteSyncFuture;
      return;
    }

    _remoteSyncFuture = _syncRemoteHistory(days: days).whenComplete(() {
      _remoteSyncFuture = null;
    });
    await _remoteSyncFuture;
  }

  Future<void> _syncRemoteHistory({required int days}) async {
    if (_evolutionApiService == null) {
      return;
    }

    final cutoff = DateTime.now().subtract(Duration(days: days));

    final chats = await _evolutionApiService.findChats();
    if (chats.isEmpty) {
      _remoteSentPhonesCache = <String>{};
      _remoteSnapshotAt = DateTime.now();
      _remoteSnapshotLookbackDays = days;
      return;
    }

    final remoteSentPhones = <String>{};
    final chatsToInspect = math.min(chats.length, _maxChatsToInspect);

    for (var i = 0; i < chatsToInspect; i++) {
      final chat = chats[i];
      final remoteJid = _extractRemoteJid(chat);
      if (remoteJid.isEmpty) {
        continue;
      }
      if (remoteJid.contains('@g.us')) {
        continue;
      }

      final normalizedPhone = _normalizePhone(remoteJid);
      if (normalizedPhone.isEmpty) {
        continue;
      }

      final chatFromMe = _extractFromMe(chat);
      var hasOutgoingMessages = false;
      if (chatFromMe == true) {
        final chatTimestamp = _extractMessageTimestamp(chat);
        hasOutgoingMessages =
            chatTimestamp != null && !chatTimestamp.isBefore(cutoff);
      }

      if (chatFromMe == false) {
        final chatText = _extractMessageText(chat);
        final chatTimestamp = _extractMessageTimestamp(chat) ?? DateTime.now();
        if (chatText.isNotEmpty) {
          await _saveIncomingReply(
            phone: normalizedPhone,
            repliedAt: chatTimestamp,
            text: chatText,
          );
        }
      }

      final messages = await _evolutionApiService.findMessages(
        remoteJid: remoteJid,
        limit: _maxMessagesPerChat,
      );

      for (final message in messages) {
        final fromMe = _extractFromMe(message);
        final text = _extractMessageText(message);
        final timestamp = _extractMessageTimestamp(message) ?? DateTime.now();

        if (fromMe == true) {
          if (!timestamp.isBefore(cutoff)) {
            hasOutgoingMessages = true;
          }
        } else if (fromMe == false && text.isNotEmpty) {
          await _saveIncomingReply(
            phone: normalizedPhone,
            repliedAt: timestamp,
            text: text,
          );
        }
      }

      if (hasOutgoingMessages) {
        remoteSentPhones.addAll(_buildPhoneMatchKeys(normalizedPhone));
      }
    }

    _remoteSentPhonesCache = remoteSentPhones;
    _remoteSnapshotAt = DateTime.now();
    _remoteSnapshotLookbackDays = days;
  }

  Future<void> _saveIncomingReply({
    required String phone,
    required DateTime repliedAt,
    required String text,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final sanitizedText = text.replaceAll(_lineBreakRegex, ' ').trim();
    if (normalizedPhone.isEmpty || sanitizedText.isEmpty) {
      return;
    }

    await _ensureHistoryDirectoryExists();
    final responsesDirectory = Directory(
      '${_historyDirectory.path}${Platform.pathSeparator}$_responsesFolderName',
    );
    if (!await responsesDirectory.exists()) {
      await responsesDirectory.create(recursive: true);
    }

    final datePart = _formatDate(repliedAt);
    final filePath =
        '${responsesDirectory.path}${Platform.pathSeparator}${normalizedPhone}_$datePart.txt';
    final file = File(filePath);
    final entry = '${_formatDateTime(repliedAt)} | $sanitizedText';

    if (await file.exists()) {
      final existingLines = await file.readAsLines();
      if (existingLines.contains(entry)) {
        return;
      }
    }

    await file.writeAsString(
      '$entry\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  String _dailyFilePath(DateTime date) {
    return '${_historyDirectory.path}${Platform.pathSeparator}${_formatDate(date)}.txt';
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateTime(DateTime date) {
    final safeDate = date.toLocal();
    final year = safeDate.year.toString().padLeft(4, '0');
    final month = safeDate.month.toString().padLeft(2, '0');
    final day = safeDate.day.toString().padLeft(2, '0');
    final hour = safeDate.hour.toString().padLeft(2, '0');
    final minute = safeDate.minute.toString().padLeft(2, '0');
    final second = safeDate.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  String _normalizePhone(String value) {
    var digits = value.replaceAll(_nonDigitsRegex, '');
    if (digits.length > 13) {
      digits = digits.substring(digits.length - 13);
    }
    return digits;
  }

  Set<String> _buildPhoneMatchKeys(String phone) {
    final digits = _normalizePhone(phone);
    if (digits.isEmpty) {
      return const <String>{};
    }

    final keys = <String>{digits};
    final candidates = <String>{digits};

    if (digits.startsWith('55') && digits.length >= 12) {
      candidates.add(digits.substring(2));
    }
    if (digits.length > 12) {
      candidates.add(digits.substring(digits.length - 12));
    }
    if (digits.length > 11) {
      candidates.add(digits.substring(digits.length - 11));
    }
    if (digits.length > 10) {
      candidates.add(digits.substring(digits.length - 10));
    }

    for (final candidate in candidates) {
      if (candidate.startsWith('55') && candidate.length >= 12) {
        _addBrazilianPhoneFamilyKeys(candidate.substring(2), keys);
      } else {
        _addBrazilianPhoneFamilyKeys(candidate, keys);
      }
    }

    return keys;
  }

  void _addBrazilianPhoneFamilyKeys(String nationalNumber, Set<String> keys) {
    if (nationalNumber.length < 10) {
      return;
    }

    final ddd = nationalNumber.substring(0, 2);
    final base8 = nationalNumber.substring(nationalNumber.length - 8);
    final withoutNinthDigit = '$ddd$base8';
    final withNinthDigit = '${ddd}9$base8';

    keys.add(withoutNinthDigit);
    keys.add(withNinthDigit);
    keys.add('55$withoutNinthDigit');
    keys.add('55$withNinthDigit');
  }

  bool _containsAny(Set<String> haystack, Set<String> needles) {
    for (final key in needles) {
      if (haystack.contains(key)) {
        return true;
      }
    }
    return false;
  }

  String _extractRemoteJid(Map<String, dynamic> payload) {
    final directCandidates = <String>[
      payload['remoteJid']?.toString() ?? '',
      payload['jid']?.toString() ?? '',
      payload['chatId']?.toString() ?? '',
      _getNestedValue(payload, const ['key', 'remoteJid'])?.toString() ?? '',
      _getNestedValue(payload, const ['conversation', 'remoteJid'])?.toString() ??
          '',
    ];

    for (final candidate in directCandidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.contains('@') || _normalizePhone(trimmed).length >= 10) {
        return trimmed;
      }
    }

    final recursiveFound = _findStringRecursively(
      payload,
      (value) => value.contains('@c.us') || value.contains('@s.whatsapp.net'),
    );
    return recursiveFound ?? '';
  }

  bool? _extractFromMe(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['fromMe'],
      _getNestedValue(payload, const ['key', 'fromMe']),
      _getNestedValue(payload, const ['message', 'key', 'fromMe']),
      _getNestedValue(payload, const ['lastMessage', 'key', 'fromMe']),
      _getNestedValue(payload, const ['lastMessage', 'fromMe']),
    ];

    for (final candidate in candidates) {
      final parsed = _parseBool(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  String _extractMessageText(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['text'],
      payload['body'],
      payload['conversation'],
      _getNestedValue(payload, const ['message', 'conversation']),
      _getNestedValue(payload, const ['message', 'extendedTextMessage', 'text']),
      _getNestedValue(payload, const ['message', 'imageMessage', 'caption']),
      _getNestedValue(payload, const ['message', 'videoMessage', 'caption']),
      _getNestedValue(payload, const ['message', 'documentMessage', 'caption']),
      _getNestedValue(payload, const ['extendedTextMessage', 'text']),
      _getNestedValue(payload, const ['lastMessage', 'text']),
      _getNestedValue(payload, const ['lastMessage', 'body']),
      _getNestedValue(payload, const ['lastMessage', 'conversation']),
    ];

    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }

  DateTime? _extractMessageTimestamp(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['messageTimestamp'],
      payload['timestamp'],
      payload['createdAt'],
      payload['updatedAt'],
      _getNestedValue(payload, const ['key', 'timestamp']),
      _getNestedValue(payload, const ['lastMessage', 'messageTimestamp']),
      _getNestedValue(payload, const ['lastMessage', 'timestamp']),
    ];

    for (final candidate in candidates) {
      final parsed = _parseDateTime(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  dynamic _getNestedValue(Map<String, dynamic> payload, List<String> path) {
    dynamic current = payload;
    for (final part in path) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      final asInt = value.toInt();
      if (asInt <= 0) {
        return null;
      }

      if (asInt > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt).toLocal();
      }

      if (asInt > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt * 1000).toLocal();
      }
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }

      final asInt = int.tryParse(trimmed);
      if (asInt != null) {
        return _parseDateTime(asInt);
      }

      final parsedIso = DateTime.tryParse(trimmed);
      if (parsedIso != null) {
        return parsedIso.toLocal();
      }
    }

    return null;
  }

  String? _findStringRecursively(
    dynamic node,
    bool Function(String value) predicate,
  ) {
    if (node is String) {
      final value = node.trim();
      if (value.isNotEmpty && predicate(value)) {
        return value;
      }
      return null;
    }

    if (node is Map) {
      for (final value in node.values) {
        final found = _findStringRecursively(value, predicate);
        if (found != null) {
          return found;
        }
      }
    }

    if (node is List) {
      for (final value in node) {
        final found = _findStringRecursively(value, predicate);
        if (found != null) {
          return found;
        }
      }
    }

    return null;
  }
}
