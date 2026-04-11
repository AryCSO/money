import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/utils/phone_utils.dart';
import '../models/chat_message_payload.dart';
import 'database_service.dart';
import 'evolution_api_service.dart';

class AutoReplyService {
  AutoReplyService({required EvolutionApiService evolutionApiService})
    : _apiService = evolutionApiService;

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

            final fromMe = _extractFromMe(message);
            if (fromMe == true) {
              final outboundMessage = _buildOutboundMessageFromPayload(
                message,
                fallbackTimestamp: timestamp,
              );
              if (outboundMessage == null) {
                continue;
              }

              final inserted = await _persistOutgoingMessage(
                phone: phone,
                sendTarget: _resolveSendTarget(
                  conversationKey: phone,
                  payload: chat,
                  remoteJid: remoteJid,
                ),
                name: chatName,
                message: outboundMessage,
              );
              if (inserted) {
                persistedMessages++;
              }
              continue;
            }

            if (fromMe != false) {
              continue;
            }

            final inboundMessage = _buildInboundMessageFromPayload(
              message,
              fallbackTimestamp: timestamp,
            );
            if (inboundMessage == null) {
              continue;
            }

            final name = inboundMessage.name.isNotEmpty
                ? inboundMessage.name
                : chatName;

            final inserted = await _persistIncomingMessage(
              phone: phone,
              sendTarget: _resolveSendTarget(
                conversationKey: phone,
                payload: chat,
                remoteJid: remoteJid,
              ),
              name: name,
              message: inboundMessage.copyWith(name: name),
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
          final fallbackOutbound = _buildOutboundMessageFromPayload(
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
          } else if (fallbackOutbound != null &&
              (visibleFrom == null ||
                  !fallbackOutbound.timestamp.isBefore(visibleFrom))) {
            final inserted = await _persistOutgoingMessage(
              phone: phone,
              sendTarget: _resolveSendTarget(
                conversationKey: phone,
                payload: chat,
                remoteJid: remoteJid,
              ),
              name: chatName,
              message: fallbackOutbound,
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
    required ChatMessagePayload payload,
    String name = '',
  }) async {
    final normalizedPhone = PhoneUtils.normalize(phone);
    final normalizedPayload = _normalizeOutgoingPayload(payload);

    if (normalizedPhone.isEmpty) {
      throw ArgumentError('Telefone invalido para envio.');
    }
    if (!_canSendPayload(normalizedPayload)) {
      throw ArgumentError('Selecione um conteudo antes de enviar.');
    }

    markAsManuallyAnswered(normalizedPhone);
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
        await _apiService.sendPresence(number: target, presence: 'composing');
        final sentPayload = await _sendManualPayload(
          target: target,
          payload: normalizedPayload,
        );
        final sentAt = DateTime.now();

        await _storeConversationPayload(
          telefone: normalizedPhone,
          nomeCliente: name,
          destinoEnvio: target,
          direcao: 'enviada_manual',
          payload: sentPayload,
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

  ChatMessagePayload _normalizeOutgoingPayload(ChatMessagePayload payload) {
    final messageType = payload.messageType.trim().isEmpty
        ? ChatMessageTypes.text
        : payload.messageType.trim();
    final content = payload.content.trim();
    final fileName = payload.fileName.trim();
    final mimeType = payload.mimeType.trim();
    final mediaUrl = payload.mediaUrl.trim();
    final locationName = payload.locationName.trim();
    final locationAddress = payload.locationAddress.trim();

    return payload.copyWith(
      content: content,
      messageType: messageType,
      fileName: fileName,
      mimeType: mimeType,
      mediaUrl: mediaUrl,
      locationName: locationName.isEmpty && payload.isLocation
          ? 'Localizacao compartilhada'
          : locationName,
      locationAddress: locationAddress,
    );
  }

  bool _canSendPayload(ChatMessagePayload payload) {
    if (payload.isLocation) {
      return payload.hasLocation;
    }
    if (payload.isMedia) {
      return payload.hasFileBytes || payload.mediaUrl.trim().isNotEmpty;
    }
    return payload.content.trim().isNotEmpty;
  }

  Future<ChatMessagePayload> _sendManualPayload({
    required String target,
    required ChatMessagePayload payload,
  }) async {
    if (payload.isText) {
      await _apiService.sendText(
        number: target,
        text: payload.content,
        delay: 0,
      );
      return payload;
    }

    if (payload.isLocation) {
      final latitude = payload.latitude;
      final longitude = payload.longitude;
      if (latitude == null || longitude == null) {
        throw ArgumentError('Localizacao invalida para envio.');
      }

      final locationName = payload.locationName.trim().isEmpty
          ? 'Localizacao compartilhada'
          : payload.locationName.trim();
      final locationAddress = payload.locationAddress.trim().isEmpty
          ? _formatCoordinates(latitude, longitude)
          : payload.locationAddress.trim();
      final response = await _apiService.sendLocation(
        number: target,
        latitude: latitude,
        longitude: longitude,
        name: locationName,
        address: locationAddress,
        delay: 0,
      );

      return payload.copyWith(
        messageId: _extractMessageId(response).isEmpty
            ? payload.messageId
            : _extractMessageId(response),
        locationName: locationName,
        locationAddress: locationAddress,
      );
    }

    if (!payload.isMedia) {
      throw ArgumentError('Tipo de mensagem nao suportado para envio manual.');
    }

    final mediaType = _mapPayloadTypeToMediaApiType(payload.messageType);
    if (mediaType.isEmpty) {
      throw ArgumentError('Tipo de anexo nao suportado para envio.');
    }

    final fileBytes = payload.fileBytes;
    if (fileBytes == null || fileBytes.isEmpty) {
      throw ArgumentError('Nao foi possivel ler o arquivo selecionado.');
    }

    final fileName = payload.fileName.trim().isEmpty
        ? _defaultFileNameForType(payload.messageType, payload.mimeType)
        : payload.fileName.trim();
    final mimeType = payload.mimeType.trim().isEmpty
        ? 'application/octet-stream'
        : payload.mimeType.trim();
    final response = await _apiService.sendMedia(
      number: target,
      mediaType: mediaType,
      fileBytes: fileBytes,
      mimeType: mimeType,
      fileName: fileName,
      caption: payload.content,
      delay: 0,
    );

    final messageId = _extractMessageId(response);
    final mediaUrl = _extractMediaUrl(response);
    final remotePayload = _extractChatMessagePayload(response);

    return payload.copyWith(
      messageId: messageId.isEmpty ? payload.messageId : messageId,
      fileName: remotePayload?.fileName.trim().isNotEmpty == true
          ? remotePayload!.fileName
          : fileName,
      mimeType: remotePayload?.mimeType.trim().isNotEmpty == true
          ? remotePayload!.mimeType
          : mimeType,
      fileSize: remotePayload?.fileSize ?? payload.fileSize,
      mediaUrl: mediaUrl.isEmpty
          ? (remotePayload?.mediaUrl ?? payload.mediaUrl)
          : mediaUrl,
    );
  }

  Future<bool> _storeConversationPayload({
    required String telefone,
    required String nomeCliente,
    required String destinoEnvio,
    required String direcao,
    required ChatMessagePayload payload,
    required DateTime registradoEm,
  }) async {
    try {
      await DatabaseService.instance.registrarMensagem(
        telefone: telefone,
        nomeCliente: nomeCliente,
        destinoEnvio: destinoEnvio,
        direcao: direcao,
        conteudo: payload.content,
        tipoMsg: payload.messageType,
        mensagemId: payload.messageId,
        arquivoNome: payload.fileName,
        arquivoMime: payload.mimeType,
        arquivoTamanho: payload.fileSize,
        arquivoDados: payload.fileBytes,
        mediaUrl: payload.mediaUrl,
        latitude: payload.latitude,
        longitude: payload.longitude,
        localNome: payload.locationName,
        localEndereco: payload.locationAddress,
        registradoEm: registradoEm,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'AutoReplyService: erro ao salvar mensagem em conversas: $e',
        );
      }
      return false;
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
            await _storeConversationPayload(
              telefone: phone,
              nomeCliente: name,
              destinoEnvio: phone,
              direcao: 'enviada_auto',
              payload: ChatMessagePayload(content: message),
              registradoEm: DateTime.now(),
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
            debugPrint(
              'AutoReplyService: erro ao enviar auto-reply para $phone: $e',
            );
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

      final candidate = _buildInboundMessageFromPayload(
        message,
        fallbackTimestamp: fallbackTimestamp,
      );
      if (candidate == null) {
        continue;
      }
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
    final payload = await _prepareIncomingPayloadForStorage(message.payload);
    return _storeConversationPayload(
      telefone: phone,
      nomeCliente: name,
      destinoEnvio: sendTarget,
      direcao: 'recebida',
      payload: payload,
      registradoEm: message.timestamp,
    );
  }

  Future<bool> _persistOutgoingMessage({
    required String phone,
    required String sendTarget,
    required String name,
    required _InboundMessage message,
  }) async {
    final payload = await _prepareIncomingPayloadForStorage(message.payload);
    return _storeConversationPayload(
      telefone: phone,
      nomeCliente: name,
      destinoEnvio: sendTarget,
      direcao: 'enviada_manual',
      payload: payload,
      registradoEm: message.timestamp,
    );
  }

  _InboundMessage? _buildInboundMessageFromPayload(
    Map<String, dynamic> payload, {
    DateTime? fallbackTimestamp,
  }) {
    final fromMe = _extractFromMe(payload);
    if (fromMe != false) {
      return null;
    }

    final messagePayload = _extractChatMessagePayload(payload);
    if (messagePayload == null || messagePayload.previewText.trim().isEmpty) {
      return null;
    }

    return _InboundMessage(
      payload: messagePayload,
      timestamp:
          _extractMessageTimestamp(payload) ??
          fallbackTimestamp ??
          DateTime.now(),
      name: _extractPushName(payload),
    );
  }

  _InboundMessage? _buildOutboundMessageFromPayload(
    Map<String, dynamic> payload, {
    DateTime? fallbackTimestamp,
  }) {
    final fromMe = _extractFromMe(payload);
    if (fromMe != true) {
      return null;
    }

    final messagePayload = _extractChatMessagePayload(payload);
    if (messagePayload == null || messagePayload.previewText.trim().isEmpty) {
      return null;
    }

    return _InboundMessage(
      payload: messagePayload,
      timestamp:
          _extractMessageTimestamp(payload) ??
          fallbackTimestamp ??
          DateTime.now(),
      name: _extractPushName(payload),
    );
  }

  Future<ChatMessagePayload> _prepareIncomingPayloadForStorage(
    ChatMessagePayload payload,
  ) async {
    if (!payload.isMedia || payload.hasFileBytes) {
      return payload;
    }

    final mediaUrl = payload.mediaUrl.trim();
    if (mediaUrl.isEmpty) {
      return payload;
    }

    final bytes = await _apiService.downloadBinary(mediaUrl);
    if (bytes == null || bytes.isEmpty) {
      return payload;
    }

    return payload.copyWith(
      fileBytes: bytes,
      fileSize: payload.fileSize > 0 ? payload.fileSize : bytes.length,
    );
  }

  ChatMessagePayload? _extractChatMessagePayload(Map<String, dynamic> payload) {
    final messageId = _extractMessageId(payload);

    final locationMessage = _extractFirstMap(<dynamic>[
      _getNested(payload, const ['message', 'locationMessage']),
      _getNested(payload, const ['message', 'liveLocationMessage']),
      payload['locationMessage'],
      payload['liveLocationMessage'],
    ]);
    if (locationMessage != null) {
      final latitude = _asDouble(
        locationMessage['degreesLatitude'] ?? locationMessage['latitude'],
      );
      final longitude = _asDouble(
        locationMessage['degreesLongitude'] ?? locationMessage['longitude'],
      );
      if (latitude != null && longitude != null) {
        return ChatMessagePayload(
          messageType: ChatMessageTypes.location,
          messageId: messageId,
          latitude: latitude,
          longitude: longitude,
          locationName: _firstNonEmptyString(<dynamic>[
            locationMessage['name'],
            payload['name'],
          ]),
          locationAddress: _firstNonEmptyString(<dynamic>[
            locationMessage['address'],
            payload['address'],
          ]),
        );
      }
    }

    final imageMessage = _extractFirstMap(<dynamic>[
      _getNested(payload, const ['message', 'imageMessage']),
      payload['imageMessage'],
    ]);
    if (imageMessage != null) {
      return _buildMediaPayload(
        payload: payload,
        messageType: ChatMessageTypes.image,
        messageMap: imageMessage,
        messageId: messageId,
      );
    }

    final videoMessage = _extractFirstMap(<dynamic>[
      _getNested(payload, const ['message', 'videoMessage']),
      payload['videoMessage'],
    ]);
    if (videoMessage != null) {
      return _buildMediaPayload(
        payload: payload,
        messageType: ChatMessageTypes.video,
        messageMap: videoMessage,
        messageId: messageId,
      );
    }

    final documentMessage = _extractFirstMap(<dynamic>[
      _getNested(payload, const ['message', 'documentMessage']),
      payload['documentMessage'],
    ]);
    if (documentMessage != null) {
      return _buildMediaPayload(
        payload: payload,
        messageType: ChatMessageTypes.document,
        messageMap: documentMessage,
        messageId: messageId,
      );
    }

    final audioMessage = _extractFirstMap(<dynamic>[
      _getNested(payload, const ['message', 'audioMessage']),
      payload['audioMessage'],
    ]);
    if (audioMessage != null) {
      return _buildMediaPayload(
        payload: payload,
        messageType: ChatMessageTypes.audio,
        messageMap: audioMessage,
        messageId: messageId,
      );
    }

    final text = _extractMessageText(payload);
    if (text.isEmpty) {
      return null;
    }

    return ChatMessagePayload(
      content: text,
      messageType: ChatMessageTypes.text,
      messageId: messageId,
    );
  }

  ChatMessagePayload _buildMediaPayload({
    required Map<String, dynamic> payload,
    required String messageType,
    required Map<String, dynamic> messageMap,
    required String messageId,
  }) {
    final mimeType = _firstNonEmptyString(<dynamic>[
      messageMap['mimetype'],
      messageMap['mimeType'],
      payload['mimetype'],
    ]);
    final fileName = _firstNonEmptyString(<dynamic>[
      messageMap['fileName'],
      messageMap['title'],
      payload['fileName'],
      _defaultFileNameForType(messageType, mimeType),
    ]);
    final mediaUrl = _extractMediaUrl(messageMap);
    final caption = _firstNonEmptyString(<dynamic>[
      messageMap['caption'],
      payload['caption'],
    ]);
    final inlineBytes = _extractInlineBytes(messageMap);

    return ChatMessagePayload(
      content: caption,
      messageType: messageType,
      messageId: messageId,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: _asInt(
        messageMap['fileLength'] ??
            messageMap['fileSize'] ??
            messageMap['size'],
      ),
      fileBytes: inlineBytes,
      mediaUrl: mediaUrl,
    );
  }

  String _extractMessageId(Map<String, dynamic> payload) {
    return _firstNonEmptyString(<dynamic>[
      payload['id'],
      _getNested(payload, const ['key', 'id']),
      _getNested(payload, const ['message', 'key', 'id']),
      _getNested(payload, const ['lastMessage', 'key', 'id']),
    ]);
  }

  String _extractMediaUrl(Map<String, dynamic> payload) {
    return _firstNonEmptyString(<dynamic>[
      payload['url'],
      payload['mediaUrl'],
      payload['directPath'],
      _getNested(payload, const ['message', 'imageMessage', 'url']),
      _getNested(payload, const ['message', 'videoMessage', 'url']),
      _getNested(payload, const ['message', 'documentMessage', 'url']),
      _getNested(payload, const ['imageMessage', 'url']),
      _getNested(payload, const ['videoMessage', 'url']),
      _getNested(payload, const ['documentMessage', 'url']),
    ]);
  }

  Uint8List? _extractInlineBytes(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['base64'],
      payload['fileData'],
      payload['data'],
    ];

    for (final candidate in candidates) {
      if (candidate is Uint8List && candidate.isNotEmpty) {
        return candidate;
      }
      if (candidate is List<int> && candidate.isNotEmpty) {
        return Uint8List.fromList(candidate);
      }
      if (candidate is String) {
        final decoded = _decodeBase64String(candidate);
        if (decoded != null && decoded.isNotEmpty) {
          return decoded;
        }
      }
    }

    return null;
  }

  Uint8List? _decodeBase64String(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.contains(',')
        ? trimmed.substring(trimmed.indexOf(',') + 1)
        : trimmed;
    try {
      return Uint8List.fromList(base64Decode(normalized));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _extractFirstMap(List<dynamic> candidates) {
    for (final candidate in candidates) {
      if (candidate is Map<String, dynamic>) {
        return candidate;
      }
      if (candidate is Map) {
        return candidate.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return null;
  }

  String _firstNonEmptyString(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    final normalized = value?.toString().trim().replaceAll(',', '.');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  String _mapPayloadTypeToMediaApiType(String payloadType) {
    switch (payloadType) {
      case ChatMessageTypes.image:
        return 'image';
      case ChatMessageTypes.video:
        return 'video';
      case ChatMessageTypes.document:
        return 'document';
      default:
        return '';
    }
  }

  String _defaultFileNameForType(String messageType, String mimeType) {
    final extension = _extensionFromMimeType(mimeType);
    final suffix = extension.isEmpty ? '' : '.$extension';
    switch (messageType) {
      case ChatMessageTypes.image:
        return 'imagem$suffix';
      case ChatMessageTypes.video:
        return 'video$suffix';
      case ChatMessageTypes.document:
        return 'documento$suffix';
      case ChatMessageTypes.audio:
        return 'audio$suffix';
      default:
        return 'arquivo$suffix';
    }
  }

  String _extensionFromMimeType(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('/')) {
      return '';
    }

    final extension = normalized.split('/').last;
    final separatorIndex = extension.indexOf(';');
    return separatorIndex >= 0
        ? extension.substring(0, separatorIndex)
        : extension;
  }

  String _formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
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
          (trimmed.contains('@') ||
              PhoneUtils.normalize(trimmed).length >= 10)) {
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
    final orderedTargets = <String>{};

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
    for (final discovered in await _discoverConversationTargets(
      conversationKey,
    )) {
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

      final matches = <String>{};
      for (final chat in chats) {
        final remoteJid = _extractRemoteJid(chat);
        if (remoteJid.isEmpty || remoteJid.contains('@g.us')) {
          continue;
        }

        final identifiers = <String>{_normalizeConversationKey(remoteJid)};
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

        final identifiers = <String>{_normalizeConversationKey(remoteJid)};
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

  Iterable<String> _extractSendTargetCandidates(
    Map<String, dynamic> payload,
  ) sync* {
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
      _getNested(payload, const [
            'message',
            'key',
            'remoteJidAlt',
          ])?.toString() ??
          '',
      _getNested(payload, const ['message', 'key', 'remoteJid'])?.toString() ??
          '',
      _getNested(payload, const [
            'message',
            'contextInfo',
            'participant',
          ])?.toString() ??
          '',
      _getNested(payload, const ['contextInfo', 'participant'])?.toString() ??
          '',
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
      _getNested(payload, const [
            'lastMessage',
            'key',
            'remoteJid',
          ])?.toString() ??
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
    required this.payload,
    required this.timestamp,
    required this.name,
  });

  final ChatMessagePayload payload;
  final DateTime timestamp;
  final String name;

  _InboundMessage copyWith({
    ChatMessagePayload? payload,
    DateTime? timestamp,
    String? name,
  }) {
    return _InboundMessage(
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      name: name ?? this.name,
    );
  }
}
