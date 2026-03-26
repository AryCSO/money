import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/utils/phone_utils.dart';
import 'database_service.dart';
import 'evolution_api_service.dart';

class AutoReplyService {
  AutoReplyService({
    required EvolutionApiService evolutionApiService,
  }) : _apiService = evolutionApiService;

  static const Duration _firstSeenMessageWindow = Duration(minutes: 2);

  final EvolutionApiService _apiService;

  final Set<String> _repliedToday = <String>{};
  final Set<String> _manuallyAnswered = <String>{};
  final Map<String, String> _pendingQueue = <String, String>{};
  final Map<String, DateTime> _lastKnownMessages = <String, DateTime>{};

  int _lastResetDay = -1;
  bool _bulkSendingActive = false;
  bool _isRunning = false;
  bool _isProcessingQueue = false;
  bool _autoReplyEnabled = false;

  Timer? _pollingTimer;
  Timer? _dailyResetTimer;

  VoidCallback? onStateChanged;

  void startMonitoring() {
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    _checkDailyReset();
    _startDailyResetTimer();
    _startPolling();
    unawaited(_checkNewMessages());
  }

  void start() {
    final wasEnabled = _autoReplyEnabled;
    _autoReplyEnabled = true;
    startMonitoring();
    if (!wasEnabled) {
      onStateChanged?.call();
    }
  }

  void stop() {
    final hadPendingQueue = _pendingQueue.isNotEmpty;
    final wasEnabled = _autoReplyEnabled;
    _autoReplyEnabled = false;
    _pendingQueue.clear();
    if (wasEnabled || hadPendingQueue) {
      onStateChanged?.call();
    }
  }

  void stopMonitoring() {
    _isRunning = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _dailyResetTimer?.cancel();
    _dailyResetTimer = null;

    final hadPendingState =
        _pendingQueue.isNotEmpty || _lastKnownMessages.isNotEmpty;
    _pendingQueue.clear();
    _lastKnownMessages.clear();
    if (hadPendingState) {
      onStateChanged?.call();
    }
  }

  void setBulkSendingActive(bool active) {
    _bulkSendingActive = active;
    if (!active && _autoReplyEnabled) {
      unawaited(_processQueue());
    }
  }

  void markAsManuallyAnswered(String phone) {
    final normalized = PhoneUtils.normalize(phone);
    final wasAdded = _manuallyAnswered.add(normalized);
    final wasRemoved = _pendingQueue.remove(normalized) != null;
    if (wasAdded || wasRemoved) {
      onStateChanged?.call();
    }
  }

  int get repliedCount => _repliedToday.length;
  int get queueCount => _pendingQueue.length;

  void resetDaily() {
    _repliedToday.clear();
    _manuallyAnswered.clear();
    _pendingQueue.clear();
    _lastKnownMessages.clear();
    onStateChanged?.call();
  }

  Future<int> syncRecentConversations({
    DateTime? visibleFrom,
    int maxChats = 80,
    int messageLimit = 20,
  }) async {
    try {
      final chats = await _apiService.findChats();
      if (chats.isEmpty) {
        return 0;
      }

      final totalChats = math.min(chats.length, maxChats);
      var persistedMessages = 0;

      for (var i = 0; i < totalChats; i++) {
        final chat = chats[i];
        final remoteJid = _extractRemoteJid(chat);
        if (remoteJid.isEmpty || remoteJid.contains('@g.us')) {
          continue;
        }

        final phone = PhoneUtils.normalize(
          remoteJid.replaceAll(RegExp(r'@.*'), ''),
        );
        if (phone.isEmpty) {
          continue;
        }

        final chatName = _extractPushName(chat);
        var latestObserved = _extractMessageTimestamp(chat);
        final previousTimestamp = _lastKnownMessages[phone];

        if (latestObserved != null) {
          if (visibleFrom != null && latestObserved.isBefore(visibleFrom)) {
            if (previousTimestamp == null ||
                latestObserved.isAfter(previousTimestamp)) {
              _lastKnownMessages[phone] = latestObserved;
            }
            continue;
          }

          if (previousTimestamp != null &&
              !latestObserved.isAfter(previousTimestamp)) {
            continue;
          }
        }

        final messages = await _apiService.findMessages(
          remoteJid: remoteJid,
          limit: messageLimit,
        );

        if (messages.isNotEmpty) {
          for (final message in messages) {
            final timestamp = _extractMessageTimestamp(message);
            if (timestamp != null &&
                (latestObserved == null || timestamp.isAfter(latestObserved))) {
              latestObserved = timestamp;
            }
            if (visibleFrom != null &&
                timestamp != null &&
                timestamp.isBefore(visibleFrom)) {
              continue;
            }

            if (_extractFromMe(message) != false) {
              continue;
            }

            final text = _extractMessageText(message);
            if (text.isEmpty) {
              continue;
            }

            final name = _extractPushName(message).isNotEmpty
                ? _extractPushName(message)
                : chatName;

            final inserted = await _persistIncomingMessage(
              phone: phone,
              sendTarget: _resolveSendTarget(
                conversationKey: phone,
                payload: chat,
                remoteJid: remoteJid,
              ),
              name: name,
              message: _InboundMessage(
                text: text,
                timestamp: timestamp ?? DateTime.now(),
                name: name,
              ),
            );
            if (inserted) {
              persistedMessages++;
            }
          }
        } else {
          final fallbackInbound = _buildInboundMessageFromPayload(
            chat,
            fallbackTimestamp: latestObserved,
          );
          if (fallbackInbound != null &&
              (visibleFrom == null ||
                  !fallbackInbound.timestamp.isBefore(visibleFrom))) {
            final inserted = await _persistIncomingMessage(
              phone: phone,
              sendTarget: _resolveSendTarget(
                conversationKey: phone,
                payload: chat,
                remoteJid: remoteJid,
              ),
              name: fallbackInbound.name.isNotEmpty
                  ? fallbackInbound.name
                  : chatName,
              message: fallbackInbound,
            );
            if (inserted) {
              persistedMessages++;
            }
          }
        }

        if (latestObserved != null) {
          if (previousTimestamp == null ||
              latestObserved.isAfter(previousTimestamp)) {
            _lastKnownMessages[phone] = latestObserved;
          }
        }
      }

      if (persistedMessages > 0) {
        onStateChanged?.call();
      }

      return persistedMessages;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'AutoReplyService: erro ao sincronizar conversas recentes: $e',
        );
      }
      return 0;
    }
  }

  Future<void> sendManualChatMessage({
    required String phone,
    String? sendTarget,
    required String text,
    String name = '',
  }) async {
    final normalizedPhone = PhoneUtils.normalize(phone);
    final content = text.trim();

    if (normalizedPhone.isEmpty) {
      throw ArgumentError('Telefone invalido para envio.');
    }
    if (content.isEmpty) {
      throw ArgumentError('Digite uma mensagem antes de enviar.');
    }

    markAsManuallyAnswered(normalizedPhone);
    final sentAt = DateTime.now();
    final targets = await _buildManualSendTargets(
      conversationKey: normalizedPhone,
      contactName: name,
      preferredTarget: sendTarget,
    );

    if (targets.isEmpty) {
      throw ArgumentError('Nao foi possivel identificar o destino deste chat.');
    }

    Object? lastError;

    for (final target in targets) {
      try {
        await _apiService.sendPresence(
          number: target,
          presence: 'composing',
        );
        await _apiService.sendText(
          number: target,
          text: content,
          delay: 0,
        );

        await DatabaseService.instance.registrarMensagem(
          telefone: normalizedPhone,
          nomeCliente: name,
          destinoEnvio: target,
          direcao: 'enviada_manual',
          conteudo: content,
          registradoEm: sentAt,
        );

        _lastKnownMessages[normalizedPhone] = sentAt;
        onStateChanged?.call();
        return;
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint(
            'AutoReplyService: erro ao enviar mensagem manual para '
            '$normalizedPhone usando "$target": $e',
          );
        }
      } finally {
        await _safePausePresence(target);
      }
    }

    if (lastError != null) {
      throw lastError;
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_checkNewMessages()),
    );
  }

  void _startDailyResetTimer() {
    _dailyResetTimer?.cancel();
    _dailyResetTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkDailyReset(),
    );
  }

  void _checkDailyReset() {
    final today = DateTime.now().day;
    if (_lastResetDay != today) {
      _lastResetDay = today;
      resetDaily();
    }
  }

  Future<void> _checkNewMessages() async {
    if (!_isRunning) {
      return;
    }

    try {
      final chats = await _apiService.findChats();
      if (!_isRunning || chats.isEmpty) {
        return;
      }

      var queueChanged = false;

      for (var i = 0; i < chats.length; i++) {
        final chat = chats[i];
        final remoteJid = _extractRemoteJid(chat);
        if (remoteJid.isEmpty || remoteJid.contains('@g.us')) {
          continue;
        }

        final phone = PhoneUtils.normalize(
          remoteJid.replaceAll(RegExp(r'@.*'), ''),
        );
        if (phone.isEmpty) {
          continue;
        }

        final latestTimestamp = _extractMessageTimestamp(chat);
        final previousTimestamp = _lastKnownMessages[phone];
        final inboundMessage = await _resolveLatestInboundMessage(
          chat: chat,
          remoteJid: remoteJid,
          fallbackTimestamp: latestTimestamp,
        );
        final observedTimestamp = latestTimestamp ?? inboundMessage?.timestamp;

        if (observedTimestamp == null) {
          _lastKnownMessages.putIfAbsent(phone, DateTime.now);
          continue;
        }

        _lastKnownMessages[phone] = observedTimestamp;

        if (inboundMessage == null) {
          continue;
        }

        final contactName = inboundMessage.name.isNotEmpty
            ? inboundMessage.name
            : _extractPushName(chat);

        await _persistIncomingMessage(
          phone: phone,
          sendTarget: _resolveSendTarget(
            conversationKey: phone,
            payload: chat,
            remoteJid: remoteJid,
          ),
          name: contactName,
          message: inboundMessage,
        );

        final shouldQueueAutoReply = previousTimestamp == null
            ? _shouldProcessFirstSeenMessage(inboundMessage.timestamp)
            : inboundMessage.timestamp.isAfter(previousTimestamp);
        if (!shouldQueueAutoReply) {
          continue;
        }
        if (!_isLatestChatInbound(
          chat: chat,
          latestInboundMessage: inboundMessage,
          latestTimestamp: observedTimestamp,
        )) {
          continue;
        }
        if (!_autoReplyEnabled) {
          continue;
        }
        if (_repliedToday.contains(phone)) {
          continue;
        }
        if (_manuallyAnswered.contains(phone)) {
          continue;
        }
        if (_pendingQueue.containsKey(phone)) {
          continue;
        }

        _pendingQueue[phone] = contactName;
        queueChanged = true;
      }

      if (queueChanged) {
        onStateChanged?.call();
        unawaited(_processQueue());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AutoReplyService: erro ao verificar mensagens: $e');
      }
    }
  }

  Future<void> _processQueue() async {
    if (!_isRunning ||
        !_autoReplyEnabled ||
        _isProcessingQueue ||
        _bulkSendingActive) {
      return;
    }
    if (_pendingQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;

    try {
      final entries = Map<String, String>.from(_pendingQueue);

      for (final entry in entries.entries) {
        if (!_isRunning || !_autoReplyEnabled || _bulkSendingActive) {
          break;
        }

        final phone = entry.key;
        final name = entry.value;

        if (_manuallyAnswered.contains(phone)) {
          _pendingQueue.remove(phone);
          onStateChanged?.call();
          continue;
        }

        final message = _buildWaitingMessage(name);

        try {
          await _apiService.sendPresence(number: phone, presence: 'composing');

          final interrupted = await _interruptibleDelay(
            Duration(milliseconds: 2000 + math.Random().nextInt(2000)),
          );
          if (interrupted) {
            await _safePausePresence(phone);
            break;
          }

          if (_manuallyAnswered.contains(phone)) {
            _pendingQueue.remove(phone);
            onStateChanged?.call();
            await _safePausePresence(phone);
            continue;
          }

          await _apiService.sendText(number: phone, text: message, delay: 0);
          await _safePausePresence(phone);

          _repliedToday.add(phone);
          _pendingQueue.remove(phone);

          try {
            await DatabaseService.instance.registrarMensagem(
              telefone: phone,
              nomeCliente: name,
              direcao: 'enviada_auto',
              conteudo: message,
            );
            await DatabaseService.instance.registrarEnvio(
              telefoneCompleto: phone,
              nomeCliente: name,
              sucesso: true,
              mensagemStatus: 'Auto-reply enviado',
              mensagemEnviada: message,
              tipo: 'auto_reply',
            );
          } catch (_) {
            // Falha de persistencia nao deve interromper o monitoramento.
          }

          onStateChanged?.call();

          final pauseBetweenReplies = await _interruptibleDelay(
            Duration(seconds: 3 + math.Random().nextInt(5)),
          );
          if (pauseBetweenReplies) {
            break;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('AutoReplyService: erro ao enviar auto-reply para $phone: $e');
          }
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<_InboundMessage?> _resolveLatestInboundMessage({
    required Map<String, dynamic> chat,
    required String remoteJid,
    DateTime? fallbackTimestamp,
  }) async {
    final directInbound = _buildInboundMessageFromPayload(
      chat,
      fallbackTimestamp: fallbackTimestamp,
    );
    if (directInbound != null) {
      return directInbound;
    }

    final messages = await _apiService.findMessages(
      remoteJid: remoteJid,
      limit: 10,
    );
    _InboundMessage? latestInbound;

    for (final message in messages) {
      final fromMe = _extractFromMe(message);
      if (fromMe != false) {
        continue;
      }

      final text = _extractMessageText(message);
      final timestamp = _extractMessageTimestamp(message) ?? fallbackTimestamp;
      if (text.isEmpty || timestamp == null) {
        continue;
      }

      final candidate = _InboundMessage(
        text: text,
        timestamp: timestamp,
        name: _extractPushName(message),
      );
      if (latestInbound == null ||
          candidate.timestamp.isAfter(latestInbound.timestamp)) {
        latestInbound = candidate;
      }
    }

    if (latestInbound != null) {
      return latestInbound;
    }

    return null;
  }

  Future<bool> _persistIncomingMessage({
    required String phone,
    required String sendTarget,
    required String name,
    required _InboundMessage message,
  }) async {
    try {
      await DatabaseService.instance.registrarMensagem(
        telefone: phone,
        nomeCliente: name,
        destinoEnvio: sendTarget,
        direcao: 'recebida',
        conteudo: message.text,
        registradoEm: message.timestamp,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'AutoReplyService: erro ao salvar mensagem recebida em conversas: $e',
        );
      }
      return false;
    }
  }

  _InboundMessage? _buildInboundMessageFromPayload(
    Map<String, dynamic> payload, {
    DateTime? fallbackTimestamp,
  }) {
    final fromMe = _extractFromMe(payload);
    if (fromMe != false) {
      return null;
    }

    final text = _extractMessageText(payload);
    if (text.isEmpty) {
      return null;
    }

    return _InboundMessage(
      text: text,
      timestamp: _extractMessageTimestamp(payload) ?? fallbackTimestamp ?? DateTime.now(),
      name: _extractPushName(payload),
    );
  }

  bool _shouldProcessFirstSeenMessage(DateTime timestamp) {
    return DateTime.now().difference(timestamp).abs() <=
        _firstSeenMessageWindow;
  }

  bool _isLatestChatInbound({
    required Map<String, dynamic> chat,
    required _InboundMessage latestInboundMessage,
    required DateTime latestTimestamp,
  }) {
    final fromMe = _extractFromMe(chat);
    if (fromMe != null) {
      return fromMe == false;
    }

    return !latestTimestamp.isAfter(latestInboundMessage.timestamp);
  }

  String _buildWaitingMessage(String name) {
    final greeting = _getGreeting();
    final pronoun = _getPronoun(name);
    final firstName = _formatName(name);

    return 'Ola, $greeting, tudo bem, $firstName? '
        'So um minuto que ja vou responder $pronoun';
  }

  String _getGreeting() {
    final now = DateTime.now();
    final totalMinutes = now.hour * 60 + now.minute;

    if (totalMinutes >= 360 && totalMinutes <= 690) {
      return 'bom dia';
    }
    if (totalMinutes >= 691 && totalMinutes <= 1070) {
      return 'boa tarde';
    }
    return 'boa noite';
  }

  String _getPronoun(String name) {
    if (name.isEmpty) {
      return 'voce';
    }

    final lower = name.trim().toLowerCase();
    final lastChar = lower[lower.length - 1];

    if (lastChar == 'a' || lastChar == 'e') {
      return 'a Sra';
    }
    if (lastChar == 'o' ||
        lower.endsWith('son') ||
        lower.endsWith('som') ||
        lower.endsWith('el')) {
      return 'o Sr';
    }

    return 'voce';
  }

  String _formatName(String name) {
    if (name.isEmpty) {
      return '';
    }

    final trimmed = name.trim();
    if (trimmed.length <= 1) {
      return trimmed.toUpperCase();
    }

    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  String _extractRemoteJid(Map<String, dynamic> payload) {
    final candidates = <String>[
      payload['remoteJid']?.toString() ?? '',
      payload['jid']?.toString() ?? '',
      payload['chatId']?.toString() ?? '',
      _getNested(payload, const ['key', 'remoteJid'])?.toString() ?? '',
      _getNested(payload, const ['conversation', 'remoteJid'])?.toString() ??
          '',
    ];

    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty &&
          (trimmed.contains('@') || PhoneUtils.normalize(trimmed).length >= 10)) {
        return trimmed;
      }
    }

    return _findStringRecursively(
          payload,
          (value) =>
              value.contains('@c.us') || value.contains('@s.whatsapp.net'),
        ) ??
        '';
  }

  bool? _extractFromMe(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['fromMe'],
      _getNested(payload, const ['key', 'fromMe']),
      _getNested(payload, const ['message', 'key', 'fromMe']),
      _getNested(payload, const ['lastMessage', 'key', 'fromMe']),
      _getNested(payload, const ['lastMessage', 'fromMe']),
    ];

    for (final candidate in candidates) {
      final parsed = _parseBool(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  String _extractPushName(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['pushName'],
      payload['name'],
      payload['notifyName'],
      _getNested(payload, const ['lastMessage', 'pushName']),
    ];

    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') {
        continue;
      }

      final parts = text.split(' ').where((part) => part.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        return parts.first;
      }
    }

    return '';
  }

  String _extractMessageText(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['text'],
      payload['body'],
      payload['conversation'],
      _getNested(payload, const ['message', 'conversation']),
      _getNested(payload, const ['message', 'extendedTextMessage', 'text']),
      _getNested(payload, const ['message', 'imageMessage', 'caption']),
      _getNested(payload, const ['message', 'videoMessage', 'caption']),
      _getNested(payload, const ['message', 'documentMessage', 'caption']),
      _getNested(payload, const ['extendedTextMessage', 'text']),
      _getNested(payload, const ['lastMessage', 'text']),
      _getNested(payload, const ['lastMessage', 'body']),
      _getNested(payload, const ['lastMessage', 'conversation']),
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
      _getNested(payload, const ['key', 'timestamp']),
      _getNested(payload, const ['message', 'key', 'timestamp']),
      _getNested(payload, const ['message', 'messageTimestamp']),
      _getNested(payload, const ['message', 'timestamp']),
      _getNested(payload, const ['lastMessage', 'messageTimestamp']),
      _getNested(payload, const ['lastMessage', 'timestamp']),
      _getNested(payload, const ['lastMessage', 'createdAt']),
      _getNested(payload, const ['lastMessage', 'updatedAt']),
    ];

    for (final candidate in candidates) {
      final parsed = _parseDateTime(candidate);
      if (parsed != null) {
        return parsed;
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

      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return null;
  }

  Future<bool> _interruptibleDelay(Duration total) async {
    const tick = Duration(milliseconds: 200);
    var remaining = total;

    while (remaining > Duration.zero) {
      if (!_isRunning || _bulkSendingActive) {
        return true;
      }

      final wait = remaining < tick ? remaining : tick;
      await Future<void>.delayed(wait);
      remaining -= wait;
    }

    return !_isRunning || _bulkSendingActive;
  }

  Future<void> _safePausePresence(String phone) async {
    try {
      if (phone.trim().isEmpty) {
        return;
      }
      await _apiService.sendPresence(number: phone, presence: 'paused');
    } catch (_) {
      // Falha ao parar presenca nao deve interromper o fluxo.
    }
  }

  String _resolveSendTarget({
    required String conversationKey,
    required Map<String, dynamic> payload,
    required String remoteJid,
  }) {
    final remoteJidPhone = _extractRemoteJidPhoneFromPayload(payload);
    if (remoteJidPhone.isNotEmpty) {
      return remoteJidPhone;
    }

    for (final candidate in _extractSendTargetCandidates(payload)) {
      final normalizedCandidate = _normalizeManualTarget(candidate);
      if (normalizedCandidate.isNotEmpty) {
        return normalizedCandidate;
      }
    }

    final remoteJidCandidate = _normalizeManualTarget(remoteJid);
    if (remoteJidCandidate.isNotEmpty) {
      return remoteJidCandidate;
    }

    return conversationKey;
  }

  Future<List<String>> _buildManualSendTargets({
    required String conversationKey,
    required String contactName,
    String? preferredTarget,
  }) async {
    final orderedTargets = LinkedHashSet<String>();

    void addTarget(String? value) {
      final resolved = _normalizeManualTarget(value);
      if (resolved.isNotEmpty) {
        orderedTargets.add(resolved);
      }
    }

    final clientPhoneCandidates = await DatabaseService.instance
        .findClientPhoneCandidatesByName(contactName);
    for (final candidate in clientPhoneCandidates) {
      addTarget(candidate);
    }

    addTarget(await _discoverRemoteJidPhoneTarget(conversationKey));
    addTarget(preferredTarget);
    for (final discovered in await _discoverConversationTargets(conversationKey)) {
      addTarget(discovered);
    }
    addTarget(conversationKey);

    return orderedTargets.toList(growable: false);
  }

  Future<List<String>> _discoverConversationTargets(
    String conversationKey,
  ) async {
    try {
      final chats = await _apiService.findChats();
      if (chats.isEmpty) {
        return const [];
      }

      final matches = LinkedHashSet<String>();
      for (final chat in chats) {
        final remoteJid = _extractRemoteJid(chat);
        if (remoteJid.isEmpty || remoteJid.contains('@g.us')) {
          continue;
        }

        final identifiers = <String>{
          _normalizeConversationKey(remoteJid),
        };
        for (final candidate in _extractSendTargetCandidates(chat)) {
          final normalized = _normalizeConversationKey(candidate);
          if (normalized.isNotEmpty) {
            identifiers.add(normalized);
          }
        }

        if (!identifiers.contains(conversationKey)) {
          continue;
        }

        for (final candidate in _extractSendTargetCandidates(chat)) {
          final normalizedCandidate = _normalizeManualTarget(candidate);
          if (normalizedCandidate.isNotEmpty) {
            matches.add(normalizedCandidate);
          }
        }

        final defaultTarget = _resolveSendTarget(
          conversationKey: conversationKey,
          payload: chat,
          remoteJid: remoteJid,
        );
        if (defaultTarget.isNotEmpty) {
          matches.add(defaultTarget);
        }

        final messages = await _apiService.findMessages(
          remoteJid: remoteJid,
          limit: 12,
        );
        for (final message in messages) {
          for (final candidate in _extractSendTargetCandidates(message)) {
            final normalizedCandidate = _normalizeManualTarget(candidate);
            if (normalizedCandidate.isNotEmpty) {
              matches.add(normalizedCandidate);
            }
          }
        }
      }

      return matches.toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'AutoReplyService: nao foi possivel descobrir destino do chat '
          '$conversationKey: $e',
        );
      }
      return const [];
    }
  }

  Future<String?> _discoverRemoteJidPhoneTarget(String conversationKey) async {
    try {
      final chats = await _apiService.findChats();
      if (chats.isEmpty) {
        return null;
      }

      for (final chat in chats) {
        final remoteJid = _extractRemoteJid(chat);
        if (remoteJid.isEmpty || remoteJid.contains('@g.us')) {
          continue;
        }

        final identifiers = <String>{
          _normalizeConversationKey(remoteJid),
        };
        for (final candidate in _extractSendTargetCandidates(chat)) {
          final normalized = _normalizeConversationKey(candidate);
          if (normalized.isNotEmpty) {
            identifiers.add(normalized);
          }
        }

        if (!identifiers.contains(conversationKey)) {
          continue;
        }

        final remoteJidPhone = _extractRemoteJidPhoneFromPayload(chat);
        if (remoteJidPhone.isNotEmpty) {
          return remoteJidPhone;
        }

        final messages = await _apiService.findMessages(
          remoteJid: remoteJid,
          limit: 12,
        );
        for (final message in messages) {
          final messageRemoteJidPhone = _extractRemoteJidPhoneFromPayload(
            message,
          );
          if (messageRemoteJidPhone.isNotEmpty) {
            return messageRemoteJidPhone;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'AutoReplyService: nao foi possivel localizar remoteJid para o chat '
          '$conversationKey: $e',
        );
      }
    }

    return null;
  }

  Iterable<String> _extractSendTargetCandidates(Map<String, dynamic> payload) sync* {
    final directCandidates = <String>[
      payload['remoteJidAlt']?.toString() ?? '',
      payload['senderPn']?.toString() ?? '',
      payload['senderLid']?.toString() ?? '',
      payload['participant']?.toString() ?? '',
      payload['remoteJid']?.toString() ?? '',
      payload['jid']?.toString() ?? '',
      payload['chatId']?.toString() ?? '',
      _getNested(payload, const ['key', 'remoteJidAlt'])?.toString() ?? '',
      _getNested(payload, const ['key', 'remoteJid'])?.toString() ?? '',
      _getNested(payload, const ['message', 'key', 'remoteJidAlt'])?.toString() ?? '',
      _getNested(payload, const ['message', 'key', 'remoteJid'])?.toString() ?? '',
      _getNested(payload, const ['message', 'contextInfo', 'participant'])?.toString() ?? '',
      _getNested(payload, const ['contextInfo', 'participant'])?.toString() ?? '',
    ];

    final seen = <String>{};
    for (final candidate in directCandidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
        continue;
      }
      if (seen.add(trimmed)) {
        yield trimmed;
      }
    }

    final recursiveMatches = <String>{};
    void collect(dynamic node) {
      if (node is String) {
        final trimmed = node.trim();
        if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
          return;
        }
        final looksLikeTarget =
            trimmed.contains('@lid') ||
            trimmed.contains('@s.whatsapp.net') ||
            trimmed.contains('@c.us');
        if (looksLikeTarget) {
          recursiveMatches.add(trimmed);
        }
        return;
      }
      if (node is Map) {
        for (final value in node.values) {
          collect(value);
        }
      } else if (node is List) {
        for (final value in node) {
          collect(value);
        }
      }
    }

    collect(payload);
    for (final candidate in recursiveMatches) {
      if (seen.add(candidate)) {
        yield candidate;
      }
    }
  }

  String _normalizeManualTarget(String? value) {
    final trimmedTarget = value?.trim() ?? '';
    if (trimmedTarget.isEmpty || trimmedTarget.toLowerCase() == 'null') {
      return '';
    }
    if (trimmedTarget.contains('@')) {
      return _extractPhoneFromWhatsAppJid(trimmedTarget);
    }

    final normalized = PhoneUtils.normalize(trimmedTarget);
    if (!_looksLikePhoneFallback(normalized)) {
      return '';
    }
    return normalized;
  }

  String _normalizeConversationKey(String value) {
    if (value.trim().isEmpty) {
      return '';
    }

    return PhoneUtils.normalize(value.replaceAll(RegExp(r'@.*'), ''));
  }

  String _extractRemoteJidPhoneFromPayload(Map<String, dynamic> payload) {
    final remoteJidCandidates = <String>[
      payload['remoteJid']?.toString() ?? '',
      _getNested(payload, const ['key', 'remoteJid'])?.toString() ?? '',
      _getNested(payload, const ['message', 'key', 'remoteJid'])?.toString() ??
          '',
      _getNested(payload, const ['lastMessage', 'key', 'remoteJid'])
              ?.toString() ??
          '',
    ];

    for (final candidate in remoteJidCandidates) {
      final phone = _extractPhoneFromWhatsAppJid(candidate);
      if (phone.isNotEmpty) {
        return phone;
      }
    }

    return '';
  }

  String _extractPhoneFromWhatsAppJid(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final normalized = trimmed.toLowerCase();
    final isWhatsAppUserJid =
        normalized.endsWith('@s.whatsapp.net') || normalized.endsWith('@c.us');
    if (!isWhatsAppUserJid) {
      return '';
    }

    final rawNumber = trimmed.split('@').first;
    final phone = PhoneUtils.normalize(rawNumber);
    if (!_looksLikePhoneFallback(phone)) {
      return '';
    }

    return phone;
  }

  bool _looksLikePhoneFallback(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 && digits.length <= 15;
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

  dynamic _getNested(Map<String, dynamic> payload, List<String> path) {
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
}

class _InboundMessage {
  const _InboundMessage({
    required this.text,
    required this.timestamp,
    required this.name,
  });

  final String text;
  final DateTime timestamp;
  final String name;
}
