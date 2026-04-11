import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/models/server_data.dart';
import '../viewmodels/auto_reply_viewmodel.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../viewmodels/template_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/result_list.dart';
import '../widgets/section_card.dart';
import '../widgets/token_chip_list.dart';
import '../widgets/whatsapp_bubble_preview.dart';
import 'chat_page.dart';
import 'connection_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ValueNotifier<bool> _allExpandedNotifier = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _allExpandedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemplateViewModel>();
    final connectionVm = context.watch<ConnectionViewModel>();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isCompactAppBar = viewportWidth < 720;
    final bodyPadding = viewportWidth < 720 ? 12.0 : 16.0;

    void openChat() {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ChatPage()));
    }

    void openConnectionSettings() {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ConnectionPage()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel de disparo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: _ConnectionStatusChip(
                connectionVm: connectionVm,
                compact: viewportWidth < 840,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Configuracoes do WhatsApp',
            onPressed: openConnectionSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
          Consumer<ThemeController>(
            builder: (context, themeCtrl, _) => IconButton(
              tooltip: themeCtrl.isDark ? 'Modo claro' : 'Modo escuro',
              onPressed: themeCtrl.toggle,
              icon: Icon(
                themeCtrl.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: isCompactAppBar
                  ? IconButton(
                      tooltip: 'Chat',
                      onPressed: openChat,
                      icon: const Icon(Icons.chat_rounded),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: openChat,
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: const Text('Chat'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF20332D),
                        foregroundColor: const Color(0xFF95F2C3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _allExpandedNotifier,
            builder: (context, expanded, _) {
              return IconButton(
                tooltip: expanded ? 'Recolher todos' : 'Expandir todos',
                icon: Icon(
                  expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
                onPressed: () {
                  _allExpandedNotifier.value = !expanded;
                },
              );
            },
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121722), Color(0xFF0E1015)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(bodyPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 1000;

                    final left = _LeftColumn(
                      vm: vm,
                      isDesktop: isDesktop,
                      allExpandedNotifier: _allExpandedNotifier,
                    );
                    final right = _RightColumn(
                      vm: vm,
                      isDesktop: isDesktop,
                      allExpandedNotifier: _allExpandedNotifier,
                    );

                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: left),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: right),
                        ],
                      );
                    }

                    return Column(
                      children: [left, const SizedBox(height: 16), right],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({
    required this.connectionVm,
    required this.compact,
  });

  final ConnectionViewModel connectionVm;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    late final IconData icon;

    if (connectionVm.isDisconnecting) {
      color = const Color(0xFFFF9F43);
      label = compact ? 'Saindo' : 'Desconectando';
      icon = Icons.logout_rounded;
    } else if (connectionVm.isLoading) {
      color = const Color(0xFF53BDEB);
      label = compact ? 'Verificando' : 'Verificando conexao';
      icon = Icons.sync_rounded;
    } else if (connectionVm.isConnected) {
      color = const Color(0xFF3ECF8E);
      label = 'Conectado';
      icon = Icons.check_circle_rounded;
    } else {
      color = const Color(0xFFFFC857);
      label = compact ? 'Offline' : 'Nao conectado';
      icon = Icons.wifi_tethering_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({
    required this.vm,
    required this.isDesktop,
    required this.allExpandedNotifier,
  });

  final TemplateViewModel vm;
  final bool isDesktop;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Column(
        children: [
          _SpreadsheetSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
          const SizedBox(height: 16),
          _MessageModelsSection(
            vm: vm,
            includePredefinedTemplates: true,
            allExpandedNotifier: allExpandedNotifier,
          ),
          const SizedBox(height: 16),
          _ResultsSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
        ],
      );
    }

    return Column(
      children: [
        _SpreadsheetSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
        const SizedBox(height: 16),
        _MessageModelsSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
        const SizedBox(height: 16),
        _ReadyTemplatesSection(
          vm: vm,
          allExpandedNotifier: allExpandedNotifier,
        ),
        const SizedBox(height: 16),
        _DynamicDataSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
        const SizedBox(height: 16),
        _DestinationIntervalSection(
          vm: vm,
          allExpandedNotifier: allExpandedNotifier,
        ),
      ],
    );
  }
}

class _MessageModelsSection extends StatefulWidget {
  const _MessageModelsSection({
    required this.vm,
    required this.allExpandedNotifier,
    this.includePredefinedTemplates = false,
  });

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;
  final bool includePredefinedTemplates;

  @override
  State<_MessageModelsSection> createState() => _MessageModelsSectionState();
}

class _MessageModelsSectionState extends State<_MessageModelsSection> {
  @override
  void initState() {
    super.initState();
    widget.vm.loadSavedModels();
  }

  void _showSaveModelDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: const Text(
          'Salvar Modelo',
          style: TextStyle(
            color: Color(0xFFEAECF0),
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFEAECF0)),
          decoration: const InputDecoration(
            labelText: 'Nome do modelo',
            hintText: 'Ex: Quitação Padrão',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF8891A4))),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                widget.vm.saveTemplateToDatabase(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return SectionCard(
      title: 'Modelo de mensagens',
      subtitle: 'Use variaveis como {NOME}, {POSI}, {BANCO}, {PARC1}...',
      icon: Icons.message_rounded,
      collapsible: true,
      expansionNotifier: widget.allExpandedNotifier,
      trailing: OutlinedButton.icon(
        onPressed: _showSaveModelDialog,
        icon: const Icon(Icons.save_rounded),
        label: const Text('Salvar'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Modelos salvos ──
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF141821),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A3347)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_rounded, size: 15, color: Color(0xFFD4AF37)),
                    const SizedBox(width: 7),
                    const Text(
                      'Modelos salvos',
                      style: TextStyle(
                        color: Color(0xFFEAECF0),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        onPressed: vm.loadSavedModels,
                        icon: const Icon(Icons.refresh_rounded, size: 15),
                        tooltip: 'Atualizar modelos',
                        padding: EdgeInsets.zero,
                        color: const Color(0xFF8891A4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (vm.savedModels.isEmpty)
                  const Text(
                    'Nenhum modelo salvo ainda.',
                    style: TextStyle(color: Color(0xFF8891A4), fontSize: 12),
                  )
                else ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: vm.savedModels.map((model) {
                      final name = model['nome']?.toString() ?? 'Sem nome';
                      final id = model['id'] is int
                          ? model['id'] as int
                          : int.tryParse(model['id']?.toString() ?? '') ?? 0;
                      return Chip(
                        label: Text(
                          name,
                          style: const TextStyle(color: Color(0xFFEAECF0), fontSize: 12),
                        ),
                        backgroundColor: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                        side: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
                        deleteIcon: const Icon(Icons.close, size: 13, color: Color(0xFF8891A4)),
                        onDeleted: () => vm.deleteSavedModel(id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: vm.savedModels.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final model = vm.savedModels[i];
                        final name = model['nome']?.toString() ?? 'Sem nome';
                        return ActionChip(
                          label: Text(
                            'Carregar "$name"',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFD4AF37)),
                          ),
                          backgroundColor: const Color(0xFF141821),
                          side: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onPressed: () => vm.loadSavedModel(model),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Campos de mensagem ──
          ...List.generate(
            6,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: vm.templateControllers[index],
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Mensagem ${index + 1}',
                  hintText: index == 0
                      ? 'Ex: Ola {NOME}, tudo bem?'
                      : 'Mensagem complementar...',
                ),
                onChanged: (_) => vm.updatePreview(),
              ),
            ),
          ),
          const SizedBox(height: 4),
          TokenChipList(tokens: vm.tokensUsed),
          if (widget.includePredefinedTemplates) ...[
            const SizedBox(height: 14),
            Divider(color: const Color(0xFFD4AF37).withValues(alpha: 0.25)),
            const SizedBox(height: 10),
            const Text(
              'Templates prontos',
              style: TextStyle(
                color: Color(0xFFC3CAD7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: predefinedTemplatesList
                  .map(
                    (template) => FilledButton.tonalIcon(
                      onPressed: () => vm.loadPredefinedTemplate(template),
                      icon: const Icon(Icons.file_copy_rounded, size: 18),
                      label: Text(template.name),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadyTemplatesSection extends StatelessWidget {
  const _ReadyTemplatesSection({
    required this.vm,
    required this.allExpandedNotifier,
  });

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Templates prontos',
      subtitle: 'Carregue um modelo base para acelerar a operacao.',
      icon: Icons.auto_awesome_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: predefinedTemplatesList
            .map(
              (template) => FilledButton.tonalIcon(
                onPressed: () => vm.loadPredefinedTemplate(template),
                icon: const Icon(Icons.file_copy_rounded, size: 18),
                label: Text(template.name),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DynamicDataSection extends StatelessWidget {
  const _DynamicDataSection({
    required this.vm,
    required this.allExpandedNotifier,
  });

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Dados dinamicos',
      subtitle: 'Valores usados para substituir variaveis no preview.',
      icon: Icons.dataset_linked_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 3 : 1;
          final fieldWidth = columns == 3
              ? (constraints.maxWidth - 24) / 3
              : constraints.maxWidth;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _dynamicField('NOME', vm.nomeController, vm, fieldWidth),
              _dynamicField('POSI', vm.posiController, vm, fieldWidth),
              _dynamicField('BANCO', vm.bancoController, vm, fieldWidth),
              _dynamicField('PARC1', vm.parc1Controller, vm, fieldWidth),
              _dynamicField('PARC2', vm.parc2Controller, vm, fieldWidth),
              _dynamicField('PARC3', vm.parc3Controller, vm, fieldWidth),
              _dynamicField('PARC4', vm.parc4Controller, vm, fieldWidth),
              _dynamicField('PARC5', vm.parc5Controller, vm, fieldWidth),
            ],
          );
        },
      ),
    );
  }

  Widget _dynamicField(
    String label,
    TextEditingController controller,
    TemplateViewModel vm,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => vm.updatePreview(),
      ),
    );
  }
}

class _DestinationIntervalSection extends StatelessWidget {
  const _DestinationIntervalSection({
    required this.vm,
    required this.allExpandedNotifier,
  });

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Destino e intervalo',
      subtitle: vm.hasSpreadsheet
          ? 'DDI e intervalos serao usados no envio em massa.'
          : 'Defina o numero e o tempo entre envios.',
      icon: Icons.send_to_mobile_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 620) {
                return Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: _phoneField(
                        controller: vm.ddiController,
                        label: 'DDI',
                        hint: '55',
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!vm.hasSpreadsheet) ...[
                      SizedBox(
                        width: 90,
                        child: _phoneField(
                          controller: vm.dddController,
                          label: 'DDD',
                          hint: '62',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _phoneField(
                          controller: vm.phoneController,
                          label: 'Numero',
                          hint: '900000000',
                        ),
                      ),
                    ],
                  ],
                );
              }

              return Column(
                children: [
                  _phoneField(
                    controller: vm.ddiController,
                    label: 'DDI',
                    hint: '55',
                  ),
                  if (!vm.hasSpreadsheet) ...[
                    const SizedBox(height: 12),
                    _phoneField(
                      controller: vm.dddController,
                      label: 'DDD',
                      hint: '62',
                    ),
                    const SizedBox(height: 12),
                    _phoneField(
                      controller: vm.phoneController,
                      label: 'Numero',
                      hint: '900000000',
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 430) {
                return Column(
                  children: [
                    _intervalField(
                      controller: vm.minIntervalController,
                      label: 'Intervalo minimo (s)',
                    ),
                    const SizedBox(height: 12),
                    _intervalField(
                      controller: vm.maxIntervalController,
                      label: 'Intervalo maximo (s)',
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _intervalField(
                      controller: vm.minIntervalController,
                      label: 'Intervalo minimo (s)',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _intervalField(
                      controller: vm.maxIntervalController,
                      label: 'Intervalo maximo (s)',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (vm.hasSpreadsheet) ...[
            if (vm.isSending && vm.sendTotal > 0) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: vm.sendProgress / vm.sendTotal,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enviando ${vm.sendProgress} de ${vm.sendTotal}...',
                      style: const TextStyle(
                        color: Color(0xFFC3CAD7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: vm.isSending
                    ? FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF7B7B),
                      )
                    : null,
                onPressed: vm.isSending
                    ? () => vm.cancelSending()
                    : () => vm.sendBulkFromSpreadsheet(),
                icon: vm.isSending
                    ? const Icon(Icons.stop_rounded)
                    : const Icon(Icons.campaign_rounded),
                label: Text(
                  vm.isSending
                      ? 'Parar envio em massa'
                      : 'Enviar para ${vm.filteredServers.length} servidor(es)',
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: vm.isSending ? null : () => vm.sendMessages(),
                icon: vm.isSending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(vm.isSending ? 'Enviando...' : 'Enviar mensagens'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phoneField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _intervalField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.vm, required this.allExpandedNotifier});

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Previa final',
      subtitle: 'Texto renderizado apos substituir as variaveis.',
      icon: Icons.preview_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      child: vm.preview.isEmpty
          ? const EmptyStateIllustration(
              icon: Icons.preview_rounded,
              title: 'Previa vazia',
              subtitle:
                  'Preencha o modelo e os dados dinamicos para visualizar a previa.',
              accentColor: AppColors.gold,
            )
          : WhatsAppBubblePreview(
              messages: vm.preview
                  .split(RegExp(r'\n\s*---\s*\n'))
                  .where((m) => m.trim().isNotEmpty)
                  .toList(),
            ),
    );
  }
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({required this.vm, required this.allExpandedNotifier});

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Resultado de envios',
      subtitle: '${vm.sendResults.length} registro(s)',
      icon: Icons.checklist_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      child: ResultList(results: vm.sendResults),
    );
  }
}

// ============================================================
// SEÇÃO DE PLANILHA (upload + filtros + resumo)
// ============================================================

class _SpreadsheetSection extends StatelessWidget {
  const _SpreadsheetSection({
    required this.vm,
    required this.allExpandedNotifier,
  });

  final TemplateViewModel vm;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Planilha de servidores',
      subtitle: vm.hasSpreadsheet
          ? '${vm.spreadsheetFileName} — ${vm.filteredServers.length} servidor(es) filtrado(s)'
          : 'Carregue um arquivo .xlsx para envio em massa.',
      icon: Icons.upload_file_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      trailing: vm.hasSpreadsheet
          ? IconButton(
              onPressed: vm.clearSpreadsheet,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Remover planilha',
              color: const Color(0xFFFF7B7B),
            )
          : null,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Botão de upload
              if (!vm.hasSpreadsheet && !vm.isLoadingSpreadsheet)
                _UploadDropZone(onTap: vm.pickAndLoadSpreadsheet),
              if (vm.isLoadingSpreadsheet && !vm.hasSpreadsheet)
                const SizedBox(height: 120),
              if (vm.hasSpreadsheet) ...[
                // ---- Filtros ----
                _FiltersRow(vm: vm),
                const SizedBox(height: 14),
                // ---- Resumo de servidores ----
                _ServerSummary(vm: vm),
              ],
            ],
          ),
          if (vm.isLoadingSpreadsheet)
            Positioned.fill(
              child: Container(
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        vm.spreadsheetLoadingMessage,
                        style: const TextStyle(
                          color: Color(0xFFC3CAD7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Aguarde...',
                        style: TextStyle(
                          color: Color(0xFF8891A4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UploadDropZone extends StatelessWidget {
  const _UploadDropZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF141821),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                size: 36,
                color: Color(0xFFD4AF37),
              ),
              SizedBox(height: 8),
              Text(
                'Clique para selecionar a planilha (.xlsx)',
                style: TextStyle(
                  color: Color(0xFFC3CAD7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Servidores sem emprestimos validos serao ignorados',
                style: TextStyle(color: Color(0xFF8891A4), fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({required this.vm});

  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 560;

        final idadeMinField = SizedBox(
          width: isWide ? 100 : double.infinity,
          child: TextField(
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Idade min',
              hintText: 'Ex: 30',
              isDense: true,
            ),
            onChanged: (v) =>
                vm.setIdadeMin(v.isEmpty ? null : int.tryParse(v)),
          ),
        );

        final idadeMaxField = SizedBox(
          width: isWide ? 100 : double.infinity,
          child: TextField(
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Idade max',
              hintText: 'Ex: 65',
              isDense: true,
            ),
            onChanged: (v) =>
                vm.setIdadeMax(v.isEmpty ? null : int.tryParse(v)),
          ),
        );

        final cidadeField = DropdownButtonFormField<String>(
          initialValue: vm.cidadeSelecionada,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Cidade', isDense: true),
          items: [
            const DropdownMenuItem(value: '', child: Text('Todas')),
            ...vm.availableCidades.map(
              (c) => DropdownMenuItem(value: c, child: Text(c)),
            ),
          ],
          onChanged: (v) => vm.setCidade(v),
        );

        if (isWide) {
          return Row(
            children: [
              idadeMinField,
              const SizedBox(width: 10),
              idadeMaxField,
              const SizedBox(width: 10),
              Expanded(child: cidadeField),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: idadeMinField),
                const SizedBox(width: 10),
                Expanded(child: idadeMaxField),
              ],
            ),
            const SizedBox(height: 10),
            cidadeField,
          ],
        );
      },
    );
  }
}

class _ServerSummary extends StatelessWidget {
  const _ServerSummary({required this.vm});

  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    final servers = vm.filteredServers;
    if (servers.isEmpty) {
      return const EmptyStateIllustration(
        icon: Icons.filter_alt_off_rounded,
        title: 'Nenhum servidor encontrado',
        subtitle: 'Ajuste os filtros de idade ou cidade para ver resultados.',
        accentColor: AppColors.error,
      );
    }

    final allSelected = servers.every((s) => s.isSelected);
    final countSelected = servers.where((s) => s.isSelected).length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF3ECF8E).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          // Selecionar todos header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F29),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF3ECF8E).withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: -8,
              children: [
                // Selecionar todos
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: servers.isEmpty ? false : allSelected,
                      onChanged: servers.isEmpty
                          ? null
                          : (val) => vm.toggleAllServers(val ?? false),
                      activeColor: const Color(0xFF3ECF8E),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text(
                      'Todos ($countSelected/${servers.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                // Masculino
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value:
                          servers
                              .where((s) => s.genero == 'Masculino')
                              .every((s) => s.isSelected) &&
                          servers.any((s) => s.genero == 'Masculino'),
                      onChanged: servers.any((s) => s.genero == 'Masculino')
                          ? (val) => vm.toggleGenderSelection(
                              'Masculino',
                              val ?? false,
                            )
                          : null,
                      activeColor: const Color(0xFF3ECF8E),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('Masc', style: TextStyle(fontSize: 12)),
                  ],
                ),
                // Feminino
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value:
                          servers
                              .where((s) => s.genero == 'Feminino')
                              .every((s) => s.isSelected) &&
                          servers.any((s) => s.genero == 'Feminino'),
                      onChanged: servers.any((s) => s.genero == 'Feminino')
                          ? (val) => vm.toggleGenderSelection(
                              'Feminino',
                              val ?? false,
                            )
                          : null,
                      activeColor: const Color(0xFF3ECF8E),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('Fem', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: servers.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 8, thickness: 0.3),
              itemBuilder: (context, index) {
                final server = servers[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  child: _ServerListItem(
                    server: server,
                    onChanged: (selected) =>
                        vm.toggleServerSelection(server, selected),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerListItem extends StatelessWidget {
  const _ServerListItem({required this.server, required this.onChanged});

  final ServerData server;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final parcs = server.parcelasFormatadas;

    Widget buildLeading() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: server.isSelected,
            onChanged: (value) => onChanged(value ?? false),
            activeColor: const Color(0xFF3ECF8E),
          ),
          const Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: Color(0xFFD4AF37),
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    Widget buildSentBadge() {
      if (!server.alreadySent) return const SizedBox.shrink();
      return Tooltip(
        message: 'Já enviado nos últimos 30 dias',
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF8891A4).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'enviado',
            style: TextStyle(
              color: Color(0xFF8891A4),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final parcelText = '${parcs.length} parc.';
        final cityText = server.municipio;

        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildLeading(),
                  Expanded(
                    child: Text(
                      server.nome,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  buildSentBadge(),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Text(
                  '$parcelText | $cityText',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC3CAD7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            buildLeading(),
            Expanded(
              child: Text(
                server.nome,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            buildSentBadge(),
            const SizedBox(width: 6),
            Text(
              parcelText,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8891A4)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                cityText,
                style: const TextStyle(fontSize: 11, color: Color(0xFFC3CAD7)),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// COLUNA DIREITA
// ============================================================

class _RightColumn extends StatelessWidget {
  const _RightColumn({
    required this.vm,
    required this.isDesktop,
    required this.allExpandedNotifier,
  });

  final TemplateViewModel vm;
  final bool isDesktop;
  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Column(
        children: [
          if (vm.feedbackMessage != null) ...[
            _FeedbackBanner(message: vm.feedbackMessage!),
            const SizedBox(height: 16),
          ],
          _DynamicDataSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
          const SizedBox(height: 16),
          _DestinationIntervalSection(
            vm: vm,
            allExpandedNotifier: allExpandedNotifier,
          ),
          const SizedBox(height: 16),
          _AutoReplySection(allExpandedNotifier: allExpandedNotifier),
          const SizedBox(height: 16),
          _PreviewSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
        ],
      );
    }

    return Column(
      children: [
        if (vm.feedbackMessage != null) ...[
          _FeedbackBanner(message: vm.feedbackMessage!),
          const SizedBox(height: 16),
        ],
        _PreviewSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
        const SizedBox(height: 16),
        _AutoReplySection(allExpandedNotifier: allExpandedNotifier),
        const SizedBox(height: 16),
        _ResultsSection(vm: vm, allExpandedNotifier: allExpandedNotifier),
      ],
    );
  }
}

class _AutoReplySection extends StatelessWidget {
  const _AutoReplySection({required this.allExpandedNotifier});

  final ValueNotifier<bool> allExpandedNotifier;

  @override
  Widget build(BuildContext context) {
    final autoReplyVm = context.watch<AutoReplyViewModel>();

    return SectionCard(
      title: 'Resposta automatica',
      subtitle: autoReplyVm.isEnabled
          ? 'Monitorando mensagens recebidas...'
          : 'Responde clientes enquanto voce trabalha.',
      icon: Icons.smart_toy_rounded,
      collapsible: true,
      expansionNotifier: allExpandedNotifier,
      trailing: Switch(
        value: autoReplyVm.isEnabled,
        onChanged: (_) => autoReplyVm.toggle(),
        activeTrackColor: const Color(0xFF3ECF8E).withValues(alpha: 0.5),
        activeThumbColor: const Color(0xFF3ECF8E),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: autoReplyVm.isEnabled
                  ? const Color(0xFF3ECF8E).withValues(alpha: 0.08)
                  : const Color(0xFF1A1F29),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: autoReplyVm.isEnabled
                    ? const Color(0xFF3ECF8E).withValues(alpha: 0.3)
                    : const Color(0xFF2A303B),
              ),
            ),
            child: Row(
              children: [
                // Indicador pulsante
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: autoReplyVm.isEnabled
                        ? const Color(0xFF3ECF8E)
                        : const Color(0xFF6B7280),
                    boxShadow: autoReplyVm.isEnabled
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF3ECF8E,
                              ).withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    autoReplyVm.isEnabled
                        ? 'Sistema ativo — monitorando mensagens'
                        : 'Sistema desativado',
                    style: TextStyle(
                      color: autoReplyVm.isEnabled
                          ? const Color(0xFF3ECF8E)
                          : const Color(0xFF8891A4),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Contadores
          LayoutBuilder(
            builder: (context, constraints) {
              final repliedCounter = _AutoReplyCounter(
                icon: Icons.check_circle_outline_rounded,
                label: 'Respondidos hoje',
                count: autoReplyVm.repliedCount,
                color: const Color(0xFF3ECF8E),
              );
              final queueCounter = _AutoReplyCounter(
                icon: Icons.hourglass_top_rounded,
                label: 'Na fila',
                count: autoReplyVm.queueCount,
                color: const Color(0xFFD4AF37),
              );

              if (constraints.maxWidth < 430) {
                return Column(
                  children: [
                    repliedCounter,
                    const SizedBox(height: 10),
                    queueCounter,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: repliedCounter),
                  const SizedBox(width: 10),
                  Expanded(child: queueCounter),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          // Informação
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F29),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funciona:',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '• Detecta mensagens de clientes novos\n'
                  '• Aguarda o envio em massa finalizar\n'
                  '• Envia saudação personalizada (nome + horário)\n'
                  '• Ignora cliente se você responder manualmente\n'
                  '• Reset automático à meia-noite',
                  style: TextStyle(
                    color: Color(0xFF8891A4),
                    fontSize: 11,
                    height: 1.5,
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

class _AutoReplyCounter extends StatelessWidget {
  const _AutoReplyCounter({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8891A4),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  count.toString(),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
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

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isError =
        message.contains('Falha') ||
        message.contains('Erro') ||
        message.contains('invalido');

    final color = isError ? const Color(0xFFFF7B7B) : const Color(0xFF3ECF8E);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
