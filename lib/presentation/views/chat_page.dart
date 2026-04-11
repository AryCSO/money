import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import '../../data/datasources/database_service.dart';
import '../../data/models/chat_message_payload.dart';
import '../viewmodels/auto_reply_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer_loading.dart';

const _kSidebarColor = AppColors.chatSidebar;
const _kHeaderColor = AppColors.chatHeader;
const _kChatBackground = AppColors.chatBackground;
const _kIncomingBubble = AppColors.chatIncomingBubble;
const _kOutgoingBubble = AppColors.chatOutgoingBubble;
const _kAccentColor = AppColors.chatAccent;
const _kTickColor = AppColors.chatTick;
const _kTextMuted = AppColors.textMuted;
const _kInputSurface = AppColors.chatInputSurface;

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final DatabaseService _database = DatabaseService.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();

  Timer? _poller;
  List<_ChatContact> _contacts = const [];
  List<_ChatContact> _filteredContacts = const [];
  List<_ChatMessage> _messages = const [];
  _ChatContact? _selectedContact;
  DateTime? _chatVisibleFrom;
  bool _loadingContacts = true;
  bool _loadingMessages = false;
  bool _isSendingMessage = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _messageController.addListener(_handleComposerChanged);
    unawaited(_refreshChat());
    _poller = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_refreshChat(silent: true)),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    _searchController.dispose();
    _messageController
      ..removeListener(_handleComposerChanged)
      ..dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  bool get _canSendMessage =>
      !_isSendingMessage &&
      _selectedContact != null &&
      _messageController.text.trim().isNotEmpty;

  bool get _canPickAttachments =>
      !_isSendingMessage && _selectedContact != null;

  Future<DateTime> _ensureChatVisibleFrom() async {
    if (_chatVisibleFrom != null) {
      return _chatVisibleFrom!;
    }

    final visibleFrom = await _database.ensureChatVisibleFrom();
    _chatVisibleFrom = visibleFrom;
    return visibleFrom;
  }

  Future<void> _refreshChat({bool silent = false}) async {
    final visibleFrom = await _ensureChatVisibleFrom();
    if (!mounted) return;
    await context.read<AutoReplyViewModel>().syncRecentConversations(
      visibleFrom: visibleFrom,
    );
    await _loadContacts(selectFirst: !silent, scrollSelectedToBottom: !silent);
  }

  Future<void> _loadContacts({
    bool selectFirst = false,
    bool scrollSelectedToBottom = false,
  }) async {
    final visibleFrom = await _ensureChatVisibleFrom();
    final rows = await _database.getChatContacts(visibleFrom: visibleFrom);
    if (!mounted) return;

    final contacts = rows.map(_ChatContact.fromMap).toList();
    final selectedPhone = _selectedContact?.phone;
    _ChatContact? selected;

    if (selectedPhone != null) {
      for (final contact in contacts) {
        if (contact.phone == selectedPhone) {
          selected = contact;
          break;
        }
      }
    }

    selected ??= selectFirst && contacts.isNotEmpty ? contacts.first : null;
    final shouldShowConversationLoader =
        selected != null &&
        (selectedPhone != selected.phone || _messages.isEmpty);

    setState(() {
      _contacts = contacts;
      _selectedContact = selected;
      _loadingContacts = false;
      _loadingMessages = shouldShowConversationLoader;
      _filteredContacts = _filterContacts(
        contacts,
        _searchController.text.trim().toLowerCase(),
      );
      if (selected == null) {
        _messages = const [];
        _loadingMessages = false;
      }
    });

    if (selected != null) {
      await _loadMessages(
        selected.phone,
        showLoader: false,
        scrollToBottom: scrollSelectedToBottom || shouldShowConversationLoader,
      );
    }
  }

  Future<void> _selectContact(_ChatContact contact) async {
    setState(() {
      _selectedContact = contact;
      _messages = const [];
      _loadingMessages = true;
    });
    _messageController.clear();
    await _loadMessages(contact.phone, scrollToBottom: true);
  }

  Future<void> _loadMessages(
    String phone, {
    bool showLoader = true,
    bool scrollToBottom = false,
  }) async {
    if (showLoader && mounted) {
      setState(() {
        _loadingMessages = true;
      });
    }

    final visibleFrom = await _ensureChatVisibleFrom();
    final rows = await _database.getConversationTimeline(
      phone,
      visibleFrom: visibleFrom,
    );
    final messages = _buildTimeline(rows);

    if (!mounted || _selectedContact?.phone != phone) return;

    setState(() {
      _messages = messages;
      _loadingMessages = false;
    });

    if (scrollToBottom) {
      _scheduleScrollToBottom();
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredContacts = _filterContacts(_contacts, query);
    });
  }

  void _handleComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) {
      return;
    }

    await _sendPayload(
      ChatMessagePayload(content: content, messageType: ChatMessageTypes.text),
    );
  }

  Future<void> _sendPayload(ChatMessagePayload payload) async {
    final contact = _selectedContact;
    if (contact == null || _isSendingMessage) {
      return;
    }

    final normalizedPayload = payload.copyWith(
      content: payload.content.trim(),
      fileName: payload.fileName.trim(),
      mimeType: payload.mimeType.trim(),
      mediaUrl: payload.mediaUrl.trim(),
      locationName: payload.locationName.trim(),
      locationAddress: payload.locationAddress.trim(),
    );

    setState(() {
      _isSendingMessage = true;
    });

    try {
      try {
        await context.read<AutoReplyViewModel>().sendManualChatMessage(
          phone: contact.phone,
          sendTarget: contact.sendTarget,
          payload: normalizedPayload,
          name: contact.name,
        );
      } catch (error) {
        if (!mounted) return;
        _showChatSnackBar(_formatChatError(error));
        return;
      }

      if (!mounted) return;

      _messageController.clear();
      setState(() {
        _messages = <_ChatMessage>[
          ..._messages,
          _ChatMessage(
            payload: normalizedPayload,
            direction: 'enviada_manual',
            sentAt: DateTime.now(),
          ),
        ];
      });
      _scheduleScrollToBottom();

      unawaited(_refreshAfterSuccessfulSend());
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Future<void> _refreshAfterSuccessfulSend() async {
    try {
      await _loadContacts(selectFirst: false, scrollSelectedToBottom: true);
    } catch (error) {
      debugPrint(
        'ChatPage: mensagem enviada, mas falha ao atualizar chat: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingMessages = false;
        });
      }
    }
  }

  Future<void> _showAttachmentOptions() async {
    if (!_canPickAttachments || !mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kHeaderColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Future<void> select(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          await action();
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Anexar ao chat',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Documentos, imagens, videos e localizacao no mesmo fluxo do WhatsApp.',
                    style: TextStyle(color: _kTextMuted, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                _AttachmentOptionTile(
                  icon: Icons.description_rounded,
                  color: const Color(0xFF7C4DFF),
                  title: 'Documento',
                  subtitle: 'TXT, planilhas, PDF, DOC e similares',
                  onTap: () => unawaited(select(_pickAndSendDocument)),
                ),
                _AttachmentOptionTile(
                  icon: Icons.image_rounded,
                  color: const Color(0xFF06D6A0),
                  title: 'Imagem',
                  subtitle: 'Foto ou imagem com legenda opcional',
                  onTap: () => unawaited(select(_pickAndSendImage)),
                ),
                _AttachmentOptionTile(
                  icon: Icons.videocam_rounded,
                  color: const Color(0xFFFF9F1C),
                  title: 'Video',
                  subtitle: 'Video com envio direto pelo chat',
                  onTap: () => unawaited(select(_pickAndSendVideo)),
                ),
                _AttachmentOptionTile(
                  icon: Icons.my_location_rounded,
                  color: const Color(0xFF00A884),
                  title: 'Local atual',
                  subtitle: 'Compartilhar a sua posicao atual',
                  onTap: () => unawaited(select(_sendCurrentLocation)),
                ),
                _AttachmentOptionTile(
                  icon: Icons.place_rounded,
                  color: const Color(0xFFFF595E),
                  title: 'Definir local',
                  subtitle: 'Informar latitude e longitude manualmente',
                  onTap: () => unawaited(select(_defineManualLocation)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'csv',
          'xls',
          'xlsx',
          'ods',
          'doc',
          'docx',
          'pdf',
          'rtf',
          'ppt',
          'pptx',
        ],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final payload = await _buildAttachmentPayload(
        result.files.single,
        fallbackType: ChatMessageTypes.document,
      );
      await _sendPayload(payload);
    } catch (error) {
      if (!mounted) return;
      _showChatSnackBar(_formatChatError(error));
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.image,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final payload = await _buildAttachmentPayload(
        result.files.single,
        fallbackType: ChatMessageTypes.image,
      );
      await _sendPayload(payload);
    } catch (error) {
      if (!mounted) return;
      _showChatSnackBar(_formatChatError(error));
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.video,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final payload = await _buildAttachmentPayload(
        result.files.single,
        fallbackType: ChatMessageTypes.video,
      );
      await _sendPayload(payload);
    } catch (error) {
      if (!mounted) return;
      _showChatSnackBar(_formatChatError(error));
    }
  }

  Future<void> _sendCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(
          'Ative o servico de localizacao do Windows para usar este envio.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissao de localizacao negada.');
      }

      final position = await Geolocator.getCurrentPosition();
      await _sendPayload(
        ChatMessagePayload(
          messageType: ChatMessageTypes.location,
          latitude: position.latitude,
          longitude: position.longitude,
          locationName: 'Localizacao atual',
          locationAddress: _messageController.text.trim().isEmpty
              ? _formatCoordinatePair(position.latitude, position.longitude)
              : _messageController.text.trim(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showChatSnackBar(_formatChatError(error));
    }
  }

  Future<void> _defineManualLocation() async {
    final nameController = TextEditingController(text: 'Localizacao manual');
    final addressController = TextEditingController(
      text: _messageController.text.trim(),
    );
    final latitudeController = TextEditingController();
    final longitudeController = TextEditingController();

    try {
      final payload = await showDialog<ChatMessagePayload>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF162128),
            title: const Text('Definir localizacao'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do local',
                        hintText: 'Ex: Escritorio central',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Endereco ou observacao',
                        hintText: 'Ex: Rua Exemplo, 123',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        hintText: 'Ex: -23.550520',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        hintText: 'Ex: -46.633308',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final latitude = _parseCoordinateValue(
                    latitudeController.text,
                  );
                  final longitude = _parseCoordinateValue(
                    longitudeController.text,
                  );
                  if (latitude == null || longitude == null) {
                    _showChatSnackBar('Informe latitude e longitude validas.');
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    ChatMessagePayload(
                      messageType: ChatMessageTypes.location,
                      latitude: latitude,
                      longitude: longitude,
                      locationName: nameController.text.trim().isEmpty
                          ? 'Localizacao manual'
                          : nameController.text.trim(),
                      locationAddress: addressController.text.trim().isEmpty
                          ? _formatCoordinatePair(latitude, longitude)
                          : addressController.text.trim(),
                    ),
                  );
                },
                child: const Text('Enviar local'),
              ),
            ],
          );
        },
      );

      if (payload != null) {
        await _sendPayload(payload);
      }
    } finally {
      nameController.dispose();
      addressController.dispose();
      latitudeController.dispose();
      longitudeController.dispose();
    }
  }

  Future<ChatMessagePayload> _buildAttachmentPayload(
    PlatformFile file, {
    required String fallbackType,
  }) async {
    final bytes = await _readPlatformFileBytes(file);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Nao foi possivel ler o arquivo selecionado.');
    }

    final detectedMime =
        lookupMimeType(
          file.name,
          headerBytes: bytes.take(32).toList(growable: false),
        ) ??
        _defaultMimeForType(fallbackType);
    final detectedType = _resolveAttachmentType(
      mimeType: detectedMime,
      fallbackType: fallbackType,
    );

    return ChatMessagePayload(
      content: _messageController.text.trim(),
      messageType: detectedType,
      fileName: file.name.trim(),
      mimeType: detectedMime,
      fileSize: file.size > 0 ? file.size : bytes.length,
      fileBytes: bytes,
    );
  }

  Future<Uint8List?> _readPlatformFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return file.bytes!;
    }

    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    return Uint8List.fromList(await File(path).readAsBytes());
  }

  String _resolveAttachmentType({
    required String mimeType,
    required String fallbackType,
  }) {
    final normalized = mimeType.toLowerCase();
    if (normalized.startsWith('image/')) {
      return ChatMessageTypes.image;
    }
    if (normalized.startsWith('video/')) {
      return ChatMessageTypes.video;
    }
    return fallbackType;
  }

  String _defaultMimeForType(String type) {
    switch (type) {
      case ChatMessageTypes.image:
        return 'image/jpeg';
      case ChatMessageTypes.video:
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  void _showChatSnackBar(String message) {
    AppToast.show(context, message: message, type: ToastType.error);
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messagesScrollController.hasClients) {
        return;
      }

      final maxScroll = _messagesScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) {
        return;
      }

      _messagesScrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<_ChatContact> _filterContacts(
    List<_ChatContact> contacts,
    String query,
  ) {
    if (query.isEmpty) return contacts;
    return contacts.where((contact) {
      return contact.name.toLowerCase().contains(query) ||
          contact.phone.toLowerCase().contains(query) ||
          contact.preview.toLowerCase().contains(query);
    }).toList();
  }

  List<_ChatMessage> _buildTimeline(List<Map<String, dynamic>> rows) {
    final timeline = <_ChatMessage>[];

    for (final row in rows) {
      final direction = (row['direcao'] ?? '').toString();
      final timestamp = _parseSqlDate(row['registrado_em']?.toString());
      final payload = ChatMessagePayload.fromMap(row);

      if (direction == 'enviada' && payload.isText) {
        final parts = payload.content.split(RegExp(r'\n\s*---\s*\n'));
        for (final part in parts) {
          final text = part.trim();
          if (text.isEmpty) continue;
          timeline.add(
            _ChatMessage(
              payload: payload.copyWith(content: text),
              direction: direction,
              sentAt: timestamp,
            ),
          );
        }
        continue;
      }

      final shouldSkip =
          payload.isText &&
          payload.content.trim().isEmpty &&
          payload.previewText.trim().isEmpty;
      if (!shouldSkip) {
        timeline.add(
          _ChatMessage(
            payload: payload,
            direction: direction,
            sentAt: timestamp,
          ),
        );
      }
    }

    return timeline;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kChatBackground,
      child: Column(
        children: [
          // Header interno do chat
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: _kHeaderColor,
              border: Border(
                bottom: BorderSide(color: AppColors.chatDivider),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Conversas',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Atualizar chats',
                  onPressed: () => unawaited(_refreshChat()),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 960;

          if (!isDesktop && _selectedContact != null) {
            return _buildConversationPane(isDesktop: false);
          }

          return Row(
            children: [
              SizedBox(
                width: isDesktop ? 340 : constraints.maxWidth,
                child: _buildContactsPane(isDesktop: isDesktop),
              ),
              if (isDesktop)
                Expanded(child: _buildConversationPane(isDesktop: true)),
            ],
          );
            },
          ),
        ),
      ],
    ),
  );
  }

  Widget _buildContactsPane({required bool isDesktop}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _kSidebarColor,
        border: Border(right: BorderSide(color: Color(0xFF25323B))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar por nome, telefone ou mensagem',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _loadingContacts
                ? const ShimmerContactList()
                : _filteredContacts.isEmpty
                ? const EmptyStateIllustration(
                    icon: Icons.forum_outlined,
                    title: 'Nenhuma conversa encontrada',
                    subtitle:
                        'Novas mensagens recebidas apos o primeiro acesso ao chat aparecem aqui.',
                    accentColor: _kAccentColor,
                  )
                : ListView.separated(
                    itemCount: _filteredContacts.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: Colors.white.withValues(alpha: 0.05)),
                    itemBuilder: (context, index) {
                      final contact = _filteredContacts[index];
                      final isSelected =
                          _selectedContact?.phone == contact.phone;
                      return _ContactTile(
                        contact: contact,
                        isSelected: isSelected,
                        onTap: () => unawaited(_selectContact(contact)),
                      );
                    },
                  ),
          ),
          if (!isDesktop)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text(
                'Selecione um cliente para abrir a conversa.',
                style: TextStyle(color: _kTextMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConversationPane({required bool isDesktop}) {
    final contact = _selectedContact;
    if (contact == null) {
      return const EmptyStateIllustration(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Escolha uma conversa',
        subtitle:
            'A lista ao lado mostra o historico acumulado desde o primeiro acesso ao chat.',
        accentColor: _kAccentColor,
      );
    }

    return Column(
      children: [
        _ConversationHeader(
          contact: contact,
          isDesktop: isDesktop,
          onBack: isDesktop
              ? null
              : () {
                  _messageController.clear();
                  setState(() {
                    _selectedContact = null;
                    _messages = const [];
                  });
                },
        ),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D171C), _kChatBackground],
              ),
            ),
            child: _loadingMessages
                ? const ShimmerMessageList()
                : _messages.isEmpty
                ? const EmptyStateIllustration(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Conversa sem mensagens salvas',
                    subtitle:
                        'As mensagens visiveis nesta janela comecam no primeiro acesso ao chat.',
                    accentColor: _kAccentColor,
                  )
                : ListView(
                    controller: _messagesScrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: _buildMessageWidgets(_messages),
                  ),
          ),
        ),
        _buildComposer(contact),
      ],
    );
  }

  Widget _buildComposer(_ChatContact contact) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(
          color: _kHeaderColor,
          border: Border(top: BorderSide(color: Color(0xFF25323B))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _kInputSurface,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Anexar ao chat',
                      onPressed: _canPickAttachments
                          ? () => unawaited(_showAttachmentOptions())
                          : null,
                      icon: const Icon(Icons.attach_file_rounded),
                      color: Colors.white,
                      disabledColor: _kTextMuted,
                    ),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          const SingleActivator(LogicalKeyboardKey.enter): () {
                            if (_canSendMessage) {
                              unawaited(_sendMessage());
                            }
                          },
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                          ): () {
                            if (_canSendMessage) {
                              unawaited(_sendMessage());
                            }
                          },
                        },
                        child: TextField(
                          controller: _messageController,
                          enabled: !_isSendingMessage,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Mensagem para ${contact.name}',
                            hintStyle: const TextStyle(color: _kTextMuted),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.fromLTRB(
                              2,
                              14,
                              16,
                              14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: _canSendMessage
                    ? () => unawaited(_sendMessage())
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccentColor,
                  foregroundColor: const Color(0xFF052C22),
                  disabledBackgroundColor: const Color(0xFF314049),
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: _isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF052C22),
                          ),
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMessageWidgets(List<_ChatMessage> messages) {
    final widgets = <Widget>[];
    DateTime? currentDay;

    for (final message in messages) {
      if (currentDay == null || !_isSameDay(currentDay, message.sentAt)) {
        currentDay = message.sentAt;
        widgets.add(_DateChip(label: _formatDayLabel(message.sentAt)));
      }

      widgets.add(_MessageBubble(message: message));
      widgets.add(const SizedBox(height: 10));
    }

    return widgets;
  }
}

class _AttachmentOptionTile extends StatelessWidget {
  const _AttachmentOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _kTextMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _kTextMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.onTap,
  });

  final _ChatContact contact;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? _kOutgoingBubble.withValues(alpha: 0.26)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _ContactAvatar(name: contact.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatListTime(contact.lastInteraction),
                style: TextStyle(
                  color: isSelected ? _kAccentColor : _kTextMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.contact,
    required this.isDesktop,
    this.onBack,
  });

  final _ChatContact contact;
  final bool isDesktop;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: _kHeaderColor,
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              tooltip: 'Voltar',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          _ContactAvatar(name: contact.name, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  contact.phone,
                  style: const TextStyle(color: _kTextMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Icon(Icons.shield_moon_outlined, color: _kTextMuted, size: 18),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isOutgoing
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final bubbleColor = message.isOutgoing
        ? _kOutgoingBubble
        : _kIncomingBubble;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(message.isOutgoing ? 18 : 4),
      bottomRight: Radius.circular(message.isOutgoing ? 4 : 18),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth =
            constraints.maxWidth * (constraints.maxWidth < 700 ? 0.84 : 0.62);

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  message.payload.isImage ? 6 : 14,
                  message.payload.isImage ? 6 : 10,
                  message.payload.isImage ? 6 : 14,
                  8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBody(),
                    const SizedBox(height: 6),
                    _BubbleFooter(
                      sentAt: message.sentAt,
                      isOutgoing: message.isOutgoing,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    final payload = message.payload;

    if (payload.isImage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: double.infinity,
              height: 220,
              child: _ImagePreview(payload: payload),
            ),
          ),
          if (payload.hasUserCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              child: Text(
                payload.content,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
        ],
      );
    }

    if (payload.isVideo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF15252B), Color(0xFF0F171B)],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.02),
                          Colors.black.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xCC111B21),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'VIDEO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FileInfoCard(
            icon: Icons.videocam_rounded,
            title: payload.fileName.isEmpty ? 'Video' : payload.fileName,
            subtitle: _formatFileInfo(payload),
          ),
          if (payload.hasUserCaption)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                payload.content,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
        ],
      );
    }

    if (payload.isDocument || payload.isAudio) {
      final title = payload.fileName.isEmpty
          ? (payload.isAudio ? 'Audio' : 'Documento')
          : payload.fileName;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FileInfoCard(
            icon: payload.isAudio
                ? Icons.mic_rounded
                : Icons.description_rounded,
            title: title,
            subtitle: _formatFileInfo(payload),
            extensionLabel: _fileExtensionLabel(title, payload.mimeType),
          ),
          if (payload.hasUserCaption)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                payload.content,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
        ],
      );
    }

    if (payload.isLocation) {
      final title = payload.locationName.trim().isEmpty
          ? 'Localizacao compartilhada'
          : payload.locationName.trim();
      final subtitle = payload.locationAddress.trim().isEmpty
          ? _formatCoordinatePair(payload.latitude ?? 0, payload.longitude ?? 0)
          : payload.locationAddress.trim();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 138,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E6F5C), Color(0xFF0F3D35)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: -24,
                  top: 20,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: -18,
                  bottom: -8,
                  child: Container(
                    width: 102,
                    height: 102,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const Center(
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    foregroundColor: Color(0xFF0F3D35),
                    child: Icon(Icons.place_rounded, size: 30),
                  ),
                ),
                if (payload.hasLocation)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.26),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _formatCoordinatePair(
                          payload.latitude!,
                          payload.longitude!,
                        ),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFFE7F4EF), height: 1.35),
          ),
        ],
      );
    }

    return Text(
      payload.content,
      textAlign: TextAlign.left,
      textWidthBasis: TextWidthBasis.longestLine,
      style: const TextStyle(fontSize: 14, height: 1.45),
    );
  }

  String _formatFileInfo(ChatMessagePayload payload) {
    final parts = <String>[];
    if (payload.fileSize > 0) {
      parts.add(_formatFileSize(payload.fileSize));
    }
    if (payload.mimeType.trim().isNotEmpty) {
      parts.add(payload.mimeType.trim());
    }
    return parts.isEmpty ? 'Arquivo compartilhado' : parts.join('  |  ');
  }

  String _fileExtensionLabel(String fileName, String mimeType) {
    final fromName = _fileExtension(fileName);
    if (fromName.isNotEmpty) {
      return fromName.toUpperCase();
    }
    if (mimeType.contains('/')) {
      return mimeType.split('/').last.toUpperCase();
    }
    return 'FILE';
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.payload});

  final ChatMessagePayload payload;

  @override
  Widget build(BuildContext context) {
    if (payload.hasFileBytes) {
      return Image.memory(
        payload.fileBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }

    if (payload.mediaUrl.trim().isNotEmpty) {
      return Image.network(
        payload.mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18313A), Color(0xFF12242B)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 42,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _FileInfoCard extends StatelessWidget {
  const _FileInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.extensionLabel = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String extensionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                if (extensionLabel.isNotEmpty)
                  Positioned(
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        extensionLabel,
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD0D9DE),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleFooter extends StatelessWidget {
  const _BubbleFooter({required this.sentAt, required this.isOutgoing});

  final DateTime sentAt;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatMessageTime(sentAt),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isOutgoing) ...[
            const SizedBox(width: 4),
            const Icon(Icons.done_all_rounded, size: 15, color: _kTickColor),
          ],
        ],
      ),
    );
  }
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.name, this.radius = 24});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF233138),
      foregroundColor: Colors.white,
      child: Text(
        _initials(name),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.58),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF182229),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFDCE5EA),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// _EmptyState removed – using EmptyStateIllustration from widgets instead

class _ChatContact {
  const _ChatContact({
    required this.phone,
    required this.sendTarget,
    required this.name,
    required this.preview,
    required this.lastInteraction,
  });

  factory _ChatContact.fromMap(Map<String, dynamic> map) {
    final phone = (map['telefone'] ?? '').toString();
    final sendTarget = (map['destino_envio'] ?? '').toString().trim();
    final name = (map['nome_cliente'] ?? '').toString().trim();
    final previewPayload = ChatMessagePayload(
      content: (map['ultima_mensagem'] ?? '').toString(),
      messageType: (map['ultimo_tipo_msg'] ?? ChatMessageTypes.text).toString(),
      fileName: (map['ultimo_arquivo_nome'] ?? '').toString(),
      locationName: (map['ultimo_local_nome'] ?? '').toString(),
    );
    final preview = previewPayload.previewText.trim();

    return _ChatContact(
      phone: phone,
      sendTarget: sendTarget,
      name: name.isEmpty ? phone : name,
      preview: preview.isEmpty ? 'Nova resposta recebida' : preview,
      lastInteraction: _parseSqlDate(map['ultima_interacao']?.toString()),
    );
  }

  final String phone;
  final String sendTarget;
  final String name;
  final String preview;
  final DateTime lastInteraction;
}

class _ChatMessage {
  const _ChatMessage({
    required this.payload,
    required this.direction,
    required this.sentAt,
  });

  final ChatMessagePayload payload;
  final String direction;
  final DateTime sentAt;

  bool get isOutgoing => direction != 'recebida';
}

DateTime _parseSqlDate(String? value) {
  if (value == null || value.trim().isEmpty) return DateTime.now();
  return DateTime.tryParse(value.replaceFirst(' ', 'T')) ?? DateTime.now();
}

String _formatMessageTime(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _formatListTime(DateTime value) {
  final now = DateTime.now();
  if (_isSameDay(now, value)) return _formatMessageTime(value);
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
}

String _formatDayLabel(DateTime value) {
  final now = DateTime.now();
  if (_isSameDay(now, value)) return 'Hoje';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(yesterday, value)) return 'Ontem';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();

  final first = parts.first.characters.first.toUpperCase();
  final last = parts.last.characters.first.toUpperCase();
  return '$first$last';
}

double? _parseCoordinateValue(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

String _formatCoordinatePair(double latitude, double longitude) {
  return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }

  const units = <String>['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  final precision = size >= 10 || unitIndex == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
}

String _fileExtension(String fileName) {
  final trimmed = fileName.trim();
  if (!trimmed.contains('.')) {
    return '';
  }

  final extension = trimmed.split('.').last.trim();
  return extension.length > 5 ? extension.substring(0, 5) : extension;
}

String _formatChatError(Object error) {
  final message = error.toString().trim();
  if (message.isEmpty) {
    return 'Nao foi possivel enviar a mensagem.';
  }

  const prefixes = <String>['Invalid argument(s): ', 'Exception: '];

  for (final prefix in prefixes) {
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }
  }

  if (message.startsWith('DioException') || message.startsWith('Exception')) {
    final firstLine = message.split('\n').first.trim();
    if (firstLine.isNotEmpty) {
      return firstLine;
    }
  }

  if (!message.startsWith('Instance of')) {
    return message;
  }

  return 'Nao foi possivel enviar a mensagem. Tente novamente.';
}
