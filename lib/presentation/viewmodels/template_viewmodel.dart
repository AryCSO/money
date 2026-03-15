import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/phone_utils.dart';
import '../../core/utils/template_engine.dart';
import '../../data/datasources/spreadsheet_service.dart';
import '../../data/models/message_job.dart';
import '../../data/models/send_result.dart';
import '../../data/models/server_data.dart';
import '../../data/models/template_variable_data.dart';
import '../../domain/usecases/send_bulk_messages_usecase.dart';

class TemplateViewModel extends ChangeNotifier {
  TemplateViewModel({required SendBulkMessagesUseCase sendBulkMessagesUseCase})
    : _sendBulkMessagesUseCase = sendBulkMessagesUseCase;

  final SendBulkMessagesUseCase _sendBulkMessagesUseCase;
  final SpreadsheetService _spreadsheetService = SpreadsheetService();

  // ---- Template controllers ----
  final templateControllers = List.generate(6, (_) => TextEditingController());
  final nomeController = TextEditingController();
  final posiController = TextEditingController();
  final bancoController = TextEditingController();
  final parc1Controller = TextEditingController();
  final parc2Controller = TextEditingController();
  final parc3Controller = TextEditingController();
  final parc4Controller = TextEditingController();
  final parc5Controller = TextEditingController();
  final ddiController = TextEditingController(text: '55');
  final dddController = TextEditingController();
  final phoneController = TextEditingController();
  final minIntervalController = TextEditingController(
    text: AppConstants.minIntervalSeconds.toString(),
  );
  final maxIntervalController = TextEditingController(
    text: AppConstants.maxIntervalSeconds.toString(),
  );

  // ---- Planilha ----
  String? spreadsheetFileName;
  List<ServerData> _allServers = [];
  List<ServerData> _filteredServers = [];
  List<String> availableCidades = [];

  // ---- Filtros ----
  int? idadeMin;
  int? idadeMax;
  String? cidadeSelecionada;

  // ---- Estado ----
  List<String> savedTemplates = List.filled(6, '');
  bool isSending = false;
  List<SendResult> sendResults = [];
  String? feedbackMessage;
  int sendProgress = 0;
  int sendTotal = 0;

  /// Retorna os servidores filtrados para exibição
  List<ServerData> get filteredServers => _filteredServers;

  /// Indica se há planilha carregada
  bool get hasSpreadsheet => _allServers.isNotEmpty;

  String get destinationNumber {
    final rawDdi = ddiController.text.trim();
    final rawDdd = dddController.text.trim();
    final rawPhone = phoneController.text.trim();
    return PhoneUtils.normalize('$rawDdi$rawDdd$rawPhone');
  }

  TemplateVariableData get currentData => TemplateVariableData(
    phone: destinationNumber,
    nome: nomeController.text,
    posi: posiController.text,
    banco: bancoController.text,
    parc1: parc1Controller.text,
    parc2: parc2Controller.text,
    parc3: parc3Controller.text,
    parc4: parc4Controller.text,
    parc5: parc5Controller.text,
  );

  List<String> get activeTemplates {
    return List.generate(
      6,
      (i) => savedTemplates[i].isNotEmpty
          ? savedTemplates[i]
          : templateControllers[i].text,
    );
  }

  String get preview {
    final templates = _nonEmptyTemplates;
    if (templates.isEmpty) return '';

    final renderedSections = templates
        .map(
          (template) =>
              TemplateEngine.render(template: template, data: currentData),
        )
        .toList();
    return renderedSections.join('\n\n---\n\n');
  }

  List<String> get _nonEmptyTemplates {
    return activeTemplates
        .map((template) => template.trim())
        .where((template) => template.isNotEmpty)
        .toList();
  }

  // =============== PLANILHA ===============

  /// Abre o file picker e carrega a planilha Excel
  Future<void> pickAndLoadSpreadsheet() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;

      // No Windows desktop, file.bytes pode ser null.
      // Nesse caso, lemos do path diretamente.
      Uint8List? bytes = file.bytes;
      if ((bytes == null || bytes.isEmpty) && file.path != null) {
        final diskFile = File(file.path!);
        if (await diskFile.exists()) {
          bytes = await diskFile.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        feedbackMessage = 'Erro: Nao foi possivel ler o arquivo.';
        notifyListeners();
        return;
      }

      spreadsheetFileName = file.name;
      _allServers = _spreadsheetService.parseExcel(bytes);

      // Extrair cidades unicas dos servidores carregados
      final cidades = <String>{};
      for (final s in _allServers) {
        if (s.municipio.isNotEmpty) cidades.add(s.municipio);
      }
      availableCidades = cidades.toList()..sort();

      // Reset filtros
      idadeMin = null;
      idadeMax = null;
      cidadeSelecionada = null;

      _applyFilters();

      feedbackMessage =
          'Planilha "${file.name}" carregada: ${_allServers.length} servidor(es) com emprestimos validos.';
      notifyListeners();
    } catch (e) {
      feedbackMessage = 'Erro ao ler planilha: $e';
      notifyListeners();
    }
  }

  /// Aplica filtros de idade e cidade
  void _applyFilters() {
    _filteredServers = _allServers.where((server) {
      // Filtro de idade
      if (idadeMin != null && server.idade < idadeMin!) return false;
      if (idadeMax != null && server.idade > idadeMax!) return false;

      // Filtro de cidade
      if (cidadeSelecionada != null &&
          cidadeSelecionada!.isNotEmpty &&
          server.municipio.toUpperCase() != cidadeSelecionada!.toUpperCase()) {
        return false;
      }

      return true;
    }).toList();

    _populatePreviewData();
  }

  void _populatePreviewData() {
    if (_filteredServers.isEmpty) return;

    final server = _filteredServers.firstWhere(
      (s) => s.isSelected,
      orElse: () => _filteredServers.first,
    );
    final parcs = server.parcelasFormatadas;

    nomeController.text = server.nome;
    posiController.text = server.cargo;
    dddController.text = server.ddd;
    phoneController.text = server.telefone;

    parc1Controller.text = parcs.isNotEmpty ? parcs[0] : '';
    parc2Controller.text = parcs.length > 1 ? parcs[1] : '';
    parc3Controller.text = parcs.length > 2 ? parcs[2] : '';
    parc4Controller.text = parcs.length > 3 ? parcs[3] : '';
    parc5Controller.text = parcs.length > 4 ? parcs[4] : '';

    updatePreview();
  }

  void setIdadeMin(int? value) {
    idadeMin = value;
    _applyFilters();
    notifyListeners();
  }

  void setIdadeMax(int? value) {
    idadeMax = value;
    _applyFilters();
    notifyListeners();
  }

  void setCidade(String? value) {
    cidadeSelecionada = (value == null || value.isEmpty) ? null : value;
    _applyFilters();
    notifyListeners();
  }

  void toggleServerSelection(ServerData server, bool selected) {
    server.isSelected = selected;
    _populatePreviewData();
    notifyListeners();
  }

  void toggleAllServers(bool selected) {
    for (var server in _filteredServers) {
      server.isSelected = selected;
    }
    _populatePreviewData();
    notifyListeners();
  }

  void toggleGenderSelection(String gender, bool selected) {
    for (var server in _filteredServers) {
      if (server.genero == gender) {
        server.isSelected = selected;
      }
    }
    _populatePreviewData();
    notifyListeners();
  }

  void clearSpreadsheet() {
    _allServers = [];
    _filteredServers = [];
    availableCidades = [];
    spreadsheetFileName = null;
    idadeMin = null;
    idadeMax = null;
    cidadeSelecionada = null;
    sendProgress = 0;
    sendTotal = 0;
    feedbackMessage = null;
    notifyListeners();
  }

  // =============== TEMPLATES ===============

  void saveTemplate() {
    for (int i = 0; i < 6; i++) {
      savedTemplates[i] = templateControllers[i].text.trim();
    }
    feedbackMessage = 'Modelo salvo com sucesso.';
    notifyListeners();
  }

  void loadPredefinedTemplate(PredefinedTemplate template) {
    for (int i = 0; i < 6; i++) {
      if (i < template.messages.length) {
        templateControllers[i].text = template.messages[i];
      } else {
        templateControllers[i].text = '';
      }
      savedTemplates[i] = '';
    }
    feedbackMessage = 'Template "${template.name}" carregado.';
    updatePreview();
  }

  void updatePreview() {
    notifyListeners();
  }

  List<String> get tokensUsed {
    final combinedText = activeTemplates.join(' ');
    return AppConstants.supportedTokens
        .where((token) => combinedText.contains(token))
        .toList();
  }

  // =============== ENVIO ===============

  /// Envia mensagem para um único número (modo manual)
  Future<void> sendMessages() async {
    final templates = _nonEmptyTemplates;
    final validationError = _validateBeforeSend(templates);
    if (validationError != null) {
      sendResults = [
        SendResult(phone: '-', success: false, message: validationError),
      ];
      feedbackMessage = validationError;
      notifyListeners();
      return;
    }

    final minInterval = int.parse(minIntervalController.text);
    final maxInterval = int.parse(maxIntervalController.text);
    final targetPhone = destinationNumber;

    isSending = true;
    feedbackMessage = null;
    sendResults = [];
    notifyListeners();

    final payloadData = currentData.copyWith(phone: targetPhone);
    final job = MessageJob(
      data: payloadData,
      renderedMessages: templates
          .map(
            (template) =>
                TemplateEngine.render(template: template, data: payloadData),
          )
          .toList(),
    );

    try {
      sendResults = await _sendBulkMessagesUseCase(
        jobs: [job],
        minIntervalSeconds: minInterval,
        maxIntervalSeconds: maxInterval,
      );

      final successCount = sendResults.where((result) => result.success).length;
      feedbackMessage = successCount > 0
          ? 'Envio concluido para $successCount numero(s).'
          : 'Falha ao enviar as mensagens.';
    } catch (_) {
      sendResults = [
        const SendResult(
          phone: '-',
          success: false,
          message: 'Erro inesperado ao enviar. Tente novamente.',
        ),
      ];
      feedbackMessage = 'Erro inesperado ao enviar.';
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  /// Envia mensagens em massa para todos os servidores filtrados da planilha
  Future<void> sendBulkFromSpreadsheet() async {
    final templates = _nonEmptyTemplates;
    if (templates.isEmpty) {
      feedbackMessage =
          'Salve ou preencha pelo menos uma mensagem antes de enviar.';
      notifyListeners();
      return;
    }

    final serversToSend = _filteredServers.where((s) => s.isSelected).toList();
    if (serversToSend.isEmpty) {
      feedbackMessage = 'Nenhum servidor selecionado para envio.';
      notifyListeners();
      return;
    }

    final minInterval =
        int.tryParse(minIntervalController.text) ??
        AppConstants.minIntervalSeconds;
    final maxInterval =
        int.tryParse(maxIntervalController.text) ??
        AppConstants.maxIntervalSeconds;
    final ddi = ddiController.text.trim().isEmpty
        ? '55'
        : ddiController.text.trim();

    isSending = true;
    feedbackMessage = null;
    sendResults = [];
    sendProgress = 0;
    sendTotal = serversToSend.length;
    notifyListeners();

    final allResults = <SendResult>[];

    for (int i = 0; i < serversToSend.length; i++) {
      final server = serversToSend[i];

      // Montar telefone: DDI + DDD da planilha + Telefone 2 da planilha
      final serverDdd = server.ddd.replaceAll(RegExp(r'\D'), '');
      final serverPhone = server.telefone.replaceAll(RegExp(r'\D'), '');

      if (serverPhone.length < 8) {
        allResults.add(
          SendResult(
            phone: '$serverDdd$serverPhone',
            success: false,
            message: 'Telefone invalido para ${server.nome}',
          ),
        );
        sendProgress = i + 1;
        notifyListeners();
        continue;
      }

      final fullNumber = PhoneUtils.normalize('$ddi$serverDdd$serverPhone');

      // Montar dados do servidor
      final parcFormatadas = server.parcelasFormatadas;
      final payloadData = TemplateVariableData(
        phone: fullNumber,
        nome: server.nome,
        posi: server.cargo,
        banco: bancoController.text.trim(),
        parc1: parcFormatadas.isNotEmpty ? parcFormatadas[0] : '',
        parc2: parcFormatadas.length > 1 ? parcFormatadas[1] : '',
        parc3: parcFormatadas.length > 2 ? parcFormatadas[2] : '',
        parc4: parcFormatadas.length > 3 ? parcFormatadas[3] : '',
        parc5: parcFormatadas.length > 4 ? parcFormatadas[4] : '',
      );

      final job = MessageJob(
        data: payloadData,
        renderedMessages: templates
            .map((t) => TemplateEngine.render(template: t, data: payloadData))
            .toList(),
      );

      try {
        // Send a single client's messages
        final results = await _sendBulkMessagesUseCase(
          jobs: [job],
          minIntervalSeconds: 0, // Delay is handled below now
          maxIntervalSeconds: 0,
        );
        allResults.addAll(results);

        // Desmarcar o cliente automaticamente se pelo menos uma mensagem foi enviada com sucesso
        if (results.any((r) => r.success)) {
          server.isSelected = false;
        }
      } catch (e) {
        allResults.add(
          SendResult(phone: fullNumber, success: false, message: 'Erro: $e'),
        );
      }

      sendProgress = i + 1;
      notifyListeners();

      // Check if user cancelled or we are moving to the next client
      if (!isSending) break;
      final isLast = i == serversToSend.length - 1;

      if (!isLast) {
        // Apply the delay here so the UI still updates progress smoothly
        final safeMin = minInterval < 1 ? 1 : minInterval;
        final safeMax = maxInterval < safeMin ? safeMin : maxInterval;
        final nextSeconds = safeMin + Random().nextInt((safeMax - safeMin) + 1);
        final nextMs = Random().nextInt(1000); // jitter

        await Future<void>.delayed(
          Duration(seconds: nextSeconds, milliseconds: nextMs),
        );
      }
    }

    sendResults = allResults;
    final successCount = allResults.where((r) => r.success).length;
    feedbackMessage =
        'Campanha finalizada: $successCount/${allResults.length} enviados com sucesso.';
    isSending = false;
    notifyListeners();
  }

  void cancelSending() {
    isSending = false;
    feedbackMessage = 'Envio cancelado pelo usuário.';
    notifyListeners();
  }

  String? _validateBeforeSend(List<String> templates) {
    if (templates.isEmpty) {
      return 'Salve ou preencha pelo menos uma mensagem antes de enviar.';
    }

    final ddi = ddiController.text.replaceAll(RegExp(r'\D'), '');
    final ddd = dddController.text.replaceAll(RegExp(r'\D'), '');
    final phone = phoneController.text.replaceAll(RegExp(r'\D'), '');

    if (ddi.length < 2) {
      return 'Informe um DDI valido (ex: 55).';
    }
    if (ddd.length < 2) {
      return 'Informe um DDD valido.';
    }
    if (phone.length < 8) {
      return 'Informe um numero de telefone valido.';
    }

    final minInterval = int.tryParse(minIntervalController.text);
    final maxInterval = int.tryParse(maxIntervalController.text);
    if (minInterval == null || maxInterval == null) {
      return 'Intervalos devem ser numeros inteiros.';
    }
    if (minInterval < 1 || maxInterval < 1) {
      return 'Intervalos precisam ser maiores que zero.';
    }
    if (maxInterval < minInterval) {
      return 'Intervalo maximo nao pode ser menor que o minimo.';
    }

    return null;
  }

  @override
  void dispose() {
    for (final controller in templateControllers) {
      controller.dispose();
    }
    nomeController.dispose();
    posiController.dispose();
    bancoController.dispose();
    parc1Controller.dispose();
    parc2Controller.dispose();
    parc3Controller.dispose();
    parc4Controller.dispose();
    parc5Controller.dispose();
    ddiController.dispose();
    dddController.dispose();
    phoneController.dispose();
    minIntervalController.dispose();
    maxIntervalController.dispose();
    super.dispose();
  }
}

class PredefinedTemplate {
  final String name;
  final List<String> messages;

  const PredefinedTemplate(this.name, this.messages);
}

const predefinedTemplatesList = [
  PredefinedTemplate('Quitacao M', [
    '{Olá|Oi|Bom dia}, {NOME}, me chamo Aryel, tudo {certo|bem} com o {Sr|senhor}?',
    '{POSI} Consegui uma condição especial de quitação {das suas parcelas|dos seus empréstimos} do *{BANCO}* no valor de:\n{PARC1}\n{PARC2}\n{PARC3}\n{PARC4}\n{PARC5}',
    '{Funciona assim|Como funciona}: {eu utilizo|nós utilizamos} recurso próprio para {quitar|abater} {seu saldo devedor|o restante das parcelas}, e {você|o senhor|o Sr} pode liberar uma margem que pode gerar um valor interessante no bolso.',
    'Posso fazer a simulacao agora para { você |o senhor|o Sr}, sem compromisso.',
    'É só me enviar o {contracheque atualizado|seu último contracheque} que ja {retorno|volto} com os valores.',
    '',
  ]),
  PredefinedTemplate('Quitacao F', [
    '{Olá|Oi|Bom dia}, {NOME}, me chamo Aryel, tudo {certo|bem} com a {Sra|senhora}?',
    '{POSI} {Gostaria de oferecer|Consegui} uma condição especial de quitação {das suas parcelas|dos seus empréstimos} do *{BANCO}* no valor de:\n{PARC1}\n{PARC2}\n{PARC3}\n{PARC4}\n{PARC5}',
    '{Funciona assim|Como funciona}: {eu utilizo|nós utilizamos} recurso próprio para {quitar|abater} {seu saldo devedor|o restante das parcelas}, e {você|a senhora|a Sra} pode liberar uma margem que pode gerar um valor interessante no bolso.',
    'Posso fazer a simulacao agora para {você|a senhora|a Sra}, sem compromisso.',
    'É só me enviar o {contracheque atualizado|seu último contracheque} que ja {retorno|volto} com os valores.',
    '',
  ]),
];
