import 'package:flutter/widgets.dart';

import '../../core/utils/gender_utils.dart';
import '../../core/utils/template_engine.dart';
import '../../data/datasources/auto_reply_service.dart';
import '../../data/datasources/database_service.dart';
import '../../data/models/chat_message_payload.dart';
import '../../data/models/pending_client.dart';
import '../../data/models/template_variable_data.dart';
import 'template_viewmodel.dart' show predefinedTemplatesList;

/// Opção de modelo de mensagem exibida na seção "seleção de modelos".
/// Unifica os modelos salvos no banco e os templates pré-definidos.
class MessageModelOption {
  const MessageModelOption({
    required this.id,
    required this.name,
    required this.messages,
  });

  /// Identificador único na lista (`db:<id>` ou `pre:<index>`).
  final String id;
  final String name;

  /// Mensagens não-vazias, em ordem.
  final List<String> messages;
}

/// ViewModel do card/modal "Clientes Pendentes" da tela inicial.
///
/// Responsável por:
/// - listar os clientes que responderam e ainda aguardam retorno (via banco);
/// - oferecer a seleção de qual modelo será disparado agora;
/// - selecionar destinatários manualmente ou por gênero (sem ocultar nomes);
/// - disparar o modelo escolhido para os selecionados.
class PendingClientsViewModel extends ChangeNotifier {
  PendingClientsViewModel({required AutoReplyService autoReplyService})
    : _autoReplyService = autoReplyService;

  final AutoReplyService _autoReplyService;
  final DatabaseService _db = DatabaseService.instance;

  /// Banco a ser usado no token {BANCO} ao montar a resposta.
  final TextEditingController bancoController = TextEditingController();

  List<PendingClient> _clients = [];
  List<PendingClient> get clients => _clients;

  List<MessageModelOption> _models = [];
  List<MessageModelOption> get models => _models;

  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;
  MessageModelOption? get selectedModel {
    for (final model in _models) {
      if (model.id == _selectedModelId) {
        return model;
      }
    }
    return null;
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isSending = false;
  bool get isSending => _isSending;

  String? _feedback;
  String? get feedback => _feedback;

  int _sendProgress = 0;
  int get sendProgress => _sendProgress;
  int _sendTotal = 0;
  int get sendTotal => _sendTotal;

  int get pendingCount => _clients.length;
  int get selectedCount => _clients.where((c) => c.isSelected).length;

  /// Carrega clientes pendentes e modelos disponíveis em paralelo.
  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();
    try {
      await Future.wait([loadPending(notify: false), loadModels(notify: false)]);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Atualiza apenas a lista de clientes pendentes (preserva seleção por
  /// telefone para não perder marcações durante um refresh automático).
  Future<void> loadPending({bool notify = true}) async {
    try {
      final previousSelection = <String, bool>{
        for (final c in _clients) c.phone: c.isSelected,
      };

      final rows = await _db.getPendingResponseClients();
      _clients = rows.map((row) {
        final name = row['nome']?.toString() ?? '';
        final phone = row['telefone']?.toString() ?? '';
        return PendingClient(
          phone: phone,
          sendTarget: row['destino_envio']?.toString() ?? '',
          name: name,
          // Genero infere-se pelo primeiro nome (sobrenome distorce a
          // heuristica por terminacao, ex.: "Joao Silva" -> 'a').
          genero: GenderUtils.fromName(_firstName(name)),
          lastMessage: row['ultima_mensagem']?.toString() ?? '',
          lastReceivedAt: _parseDate(row['last_in']),
          isSelected: previousSelection[phone] ?? false,
        );
      }).toList();
    } catch (e) {
      debugPrint('PendingClientsViewModel.loadPending erro: $e');
      _clients = [];
    }
    if (notify) {
      notifyListeners();
    }
  }

  /// Carrega modelos salvos no banco + templates pré-definidos.
  Future<void> loadModels({bool notify = true}) async {
    final options = <MessageModelOption>[];

    for (var i = 0; i < predefinedTemplatesList.length; i++) {
      final tpl = predefinedTemplatesList[i];
      final msgs = tpl.messages
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toList();
      if (msgs.isNotEmpty) {
        options.add(
          MessageModelOption(id: 'pre:$i', name: tpl.name, messages: msgs),
        );
      }
    }

    try {
      final saved = await _db.listarModelos();
      for (final model in saved) {
        final id = model['id']?.toString() ?? '';
        final name = (model['nome']?.toString().trim().isNotEmpty == true)
            ? model['nome'].toString()
            : 'Sem nome';
        final msgs = <String>[];
        for (var i = 1; i <= 6; i++) {
          final text = (model['msg$i']?.toString() ?? '').trim();
          if (text.isNotEmpty && text != '[]' && text != 'null') {
            msgs.add(text);
          }
        }
        if (msgs.isNotEmpty) {
          options.add(
            MessageModelOption(id: 'db:$id', name: name, messages: msgs),
          );
        }
      }
    } catch (e) {
      debugPrint('PendingClientsViewModel.loadModels erro: $e');
    }

    _models = options;
    if (_selectedModelId == null && _models.isNotEmpty) {
      _selectedModelId = _models.first.id;
    }
    if (notify) {
      notifyListeners();
    }
  }

  void selectModel(String id) {
    _selectedModelId = id;
    notifyListeners();
  }

  void toggleClient(PendingClient client, bool selected) {
    client.isSelected = selected;
    notifyListeners();
  }

  void toggleAll(bool selected) {
    for (final client in _clients) {
      client.isSelected = selected;
    }
    notifyListeners();
  }

  /// Seleciona destinatários por gênero SEM ocultar os demais.
  ///
  /// Regra do produto: ao escolher "Masculino" ou "Feminino", a lista continua
  /// mostrando todos os nomes, mas apenas os do gênero escolhido ficam
  /// marcados. Isso permite corrigir manualmente classificações erradas.
  /// 'todos' marca todos.
  void selectByGender(String gender) {
    for (final client in _clients) {
      if (gender == 'todos') {
        client.isSelected = true;
      } else if (gender == 'M') {
        client.isSelected = client.isMasculino;
      } else if (gender == 'F') {
        client.isSelected = client.isFeminino;
      }
    }
    notifyListeners();
  }

  /// Dispara o modelo selecionado para os clientes marcados.
  Future<void> sendToSelected() async {
    final model = selectedModel;
    if (model == null || model.messages.isEmpty) {
      _feedback = 'Selecione um modelo de mensagem antes de enviar.';
      notifyListeners();
      return;
    }

    final targets = _clients.where((c) => c.isSelected).toList();
    if (targets.isEmpty) {
      _feedback = 'Nenhum cliente selecionado.';
      notifyListeners();
      return;
    }

    _isSending = true;
    _feedback = null;
    _sendProgress = 0;
    _sendTotal = targets.length;
    notifyListeners();

    final banco = bancoController.text.trim();
    var success = 0;

    for (final client in targets) {
      final data = TemplateVariableData(
        phone: client.phone,
        // Exibimos o nome completo, mas o envio usa apenas o primeiro nome.
        nome: _firstName(client.name),
        posi: '',
        banco: banco,
        parc1: '',
        parc2: '',
        parc3: '',
        parc4: '',
        parc5: '',
      );

      try {
        for (final template in model.messages) {
          final text = TemplateEngine.render(template: template, data: data)
              .trim();
          if (text.isEmpty) {
            continue;
          }
          await _autoReplyService.sendManualChatMessage(
            phone: client.phone,
            sendTarget: client.sendTarget.isEmpty ? null : client.sendTarget,
            name: client.name,
            payload: ChatMessagePayload(content: text),
          );
          // Pequeno respiro entre mensagens encadeadas do mesmo contato.
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
        success++;
      } catch (e) {
        debugPrint(
          'PendingClientsViewModel: falha ao responder ${client.phone}: $e',
        );
      }

      _sendProgress++;
      notifyListeners();
    }

    // Os contatos respondidos saem da lista no próximo carregamento.
    await loadPending(notify: false);

    _isSending = false;
    _feedback = 'Resposta enviada para $success de ${targets.length} cliente(s).';
    notifyListeners();
  }

  /// Extrai o primeiro nome de um nome completo (para token {NOME} e genero).
  String _firstName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.first;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value.replaceFirst(' ', 'T'))?.toLocal();
    }
    return null;
  }

  @override
  void dispose() {
    bancoController.dispose();
    super.dispose();
  }
}
