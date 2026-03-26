import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/datasources/database_service.dart';
import '../viewmodels/auto_reply_viewmodel.dart';

const _kSidebarColor = Color(0xFF111B21);
const _kHeaderColor = Color(0xFF202C33);
const _kChatBackground = Color(0xFF0B141A);
const _kIncomingBubble = Color(0xFF202C33);
const _kOutgoingBubble = Color(0xFF005C4B);
const _kAccentColor = Color(0xFF25D366);
const _kTextMuted = Color(0xFF8696A0);

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
    await context.read<AutoReplyViewModel>().syncRecentConversations(
          visibleFrom: visibleFrom,
        );
    await _loadContacts(
      selectFirst: !silent,
      scrollSelectedToBottom: !silent,
    );
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
        selected != null && (selectedPhone != selected.phone || _messages.isEmpty);

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
    final contact = _selectedContact;
    final content = _messageController.text.trim();
    if (contact == null || content.isEmpty || _isSendingMessage) {
      return;
    }

    setState(() {
      _isSendingMessage = true;
    });

    try {
      try {
        await context.read<AutoReplyViewModel>().sendManualChatMessage(
              phone: contact.phone,
              sendTarget: contact.sendTarget,
              text: content,
              name: contact.name,
            );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_formatChatError(error))),
        );
        return;
      }

      if (!mounted) return;

      _messageController.clear();
      setState(() {
        _messages = <_ChatMessage>[
          ..._messages,
          _ChatMessage(
            content: content,
            direction: 'enviada_manual',
            sentAt: DateTime.now(),
          ),
        ];
      });
      _scheduleScrollToBottom();

      unawaited(_refreshAfterSuccessfulSend());
    } finally {
      if (!mounted) return;
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  Future<void> _refreshAfterSuccessfulSend() async {
    try {
      await _loadContacts(
        selectFirst: false,
        scrollSelectedToBottom: true,
      );
    } catch (error) {
      debugPrint('ChatPage: mensagem enviada, mas falha ao atualizar chat: $error');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
      });
    }
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

  List<_ChatContact> _filterContacts(List<_ChatContact> contacts, String query) {
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
      final content = (row['conteudo'] ?? '').toString();
      final timestamp = _parseSqliteDate(row['registrado_em']?.toString());
      final parts = direction == 'enviada'
          ? content.split(RegExp(r'\n\s*---\s*\n'))
          : [content];

      for (final part in parts) {
        final text = part.trim();
        if (text.isEmpty) continue;
        timeline.add(
          _ChatMessage(
            content: text,
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
    return Scaffold(
      backgroundColor: _kChatBackground,
      appBar: AppBar(
        backgroundColor: _kHeaderColor,
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: 'Atualizar chats',
            onPressed: () => unawaited(_refreshChat()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
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
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            color: _kHeaderColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Conversas recebidas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'O historico exibido comeca no seu primeiro acesso ao chat.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
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
                ? const Center(child: CircularProgressIndicator())
                : _filteredContacts.isEmpty
                ? const _EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'Nenhuma conversa encontrada',
                    subtitle:
                        'Novas mensagens recebidas apos o primeiro acesso ao chat aparecem aqui.',
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
      return const _EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Escolha uma conversa',
        subtitle:
            'A lista ao lado mostra o historico acumulado desde o primeiro acesso ao chat.',
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
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const _EmptyState(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Conversa sem mensagens salvas',
                    subtitle:
                        'As mensagens visiveis nesta janela comecam no primeiro acesso ao chat.',
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
                  color: const Color(0xFF2A3942),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: TextField(
                  controller: _messageController,
                  enabled: !_isSendingMessage,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Mensagem para ${contact.name}',
                    hintStyle: const TextStyle(color: _kTextMuted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: _canSendMessage ? () => unawaited(_sendMessage()) : null,
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
    final bubbleColor =
        message.isOutgoing ? _kOutgoingBubble : _kIncomingBubble;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(message.isOutgoing ? 18 : 4),
      bottomRight: Radius.circular(message.isOutgoing ? 4 : 18),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth *
            (constraints.maxWidth < 700 ? 0.84 : 0.62);

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      message.content,
                      textAlign: TextAlign.left,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatMessageTime(message.sentAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
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
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.58,
        ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: _kAccentColor),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextMuted, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final preview = (map['ultima_mensagem'] ?? '').toString().trim();

    return _ChatContact(
      phone: phone,
      sendTarget: sendTarget,
      name: name.isEmpty ? phone : name,
      preview: preview.isEmpty ? 'Nova resposta recebida' : preview,
      lastInteraction: _parseSqliteDate(map['ultima_interacao']?.toString()),
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
    required this.content,
    required this.direction,
    required this.sentAt,
  });

  final String content;
  final String direction;
  final DateTime sentAt;

  bool get isOutgoing => direction != 'recebida';
}

DateTime _parseSqliteDate(String? value) {
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

String _formatChatError(Object error) {
  final message = error.toString().trim();
  if (message.isEmpty) {
    return 'Nao foi possivel enviar a mensagem.';
  }

  const prefixes = <String>[
    'Invalid argument(s): ',
    'Exception: ',
  ];

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
