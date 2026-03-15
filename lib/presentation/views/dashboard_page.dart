import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../viewmodels/template_viewmodel.dart';
import '../widgets/result_list.dart';
import '../widgets/section_card.dart';
import '../widgets/token_chip_list.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemplateViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Painel de disparo')),
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
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 1000;

                    final left = _LeftColumn(vm: vm);
                    final right = _RightColumn(vm: vm);

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

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({required this.vm});

  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ============ UPLOAD DE PLANILHA ============
        _SpreadsheetSection(vm: vm),
        const SizedBox(height: 16),

        // ============ MODELOS DE MENSAGEM ============
        SectionCard(
          title: 'Modelos de mensagem',
          subtitle: 'Use variaveis como {NOME}, {POSI}, {BANCO}, {PARC1}...',
          icon: Icons.message_rounded,
          trailing: OutlinedButton.icon(
            onPressed: vm.saveTemplate,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Salvar'),
          ),
          child: Column(
            children: [
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Templates prontos',
          subtitle: 'Carregue um modelo base para acelerar a operacao.',
          icon: Icons.auto_awesome_rounded,
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
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Dados dinamicos',
          subtitle: 'Valores usados para substituir variaveis no preview.',
          icon: Icons.dataset_linked_rounded,
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
                  _field('NOME', vm.nomeController, vm, fieldWidth),
                  _field('POSI', vm.posiController, vm, fieldWidth),
                  _field('BANCO', vm.bancoController, vm, fieldWidth),
                  _field('PARC1', vm.parc1Controller, vm, fieldWidth),
                  _field('PARC2', vm.parc2Controller, vm, fieldWidth),
                  _field('PARC3', vm.parc3Controller, vm, fieldWidth),
                  _field('PARC4', vm.parc4Controller, vm, fieldWidth),
                  _field('PARC5', vm.parc5Controller, vm, fieldWidth),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Destino e intervalo',
          subtitle: vm.hasSpreadsheet
              ? 'DDI e intervalos serao usados no envio em massa.'
              : 'Defina o numero e o tempo entre envios.',
          icon: Icons.send_to_mobile_rounded,
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
              Row(
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
              ),
              const SizedBox(height: 16),

              // Botão de envio – troca entre manual e em massa
              if (vm.hasSpreadsheet) ...[
                // Barra de progresso
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
                        ? FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7B7B))
                        : null,
                    onPressed:
                        vm.isSending
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
                    label: Text(
                      vm.isSending ? 'Enviando...' : 'Enviar mensagens',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
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

// ============================================================
// SEÇÃO DE PLANILHA (upload + filtros + resumo)
// ============================================================

class _SpreadsheetSection extends StatelessWidget {
  const _SpreadsheetSection({required this.vm});

  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Planilha de servidores',
      subtitle: vm.hasSpreadsheet
          ? '${vm.spreadsheetFileName} — ${vm.filteredServers.length} servidor(es) filtrado(s)'
          : 'Carregue um arquivo .xlsx para envio em massa.',
      icon: Icons.upload_file_rounded,
      trailing: vm.hasSpreadsheet
          ? IconButton(
              onPressed: vm.clearSpreadsheet,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Remover planilha',
              color: const Color(0xFFFF7B7B),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Botão de upload
          if (!vm.hasSpreadsheet)
            _UploadDropZone(onTap: vm.pickAndLoadSpreadsheet)
          else ...[
            // ---- Filtros ----
            _FiltersRow(vm: vm),
            const SizedBox(height: 14),
            // ---- Resumo de servidores ----
            _ServerSummary(vm: vm),
          ],
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
                'Servidores sem emprestimos ou com marcação de cor serão ignorados',
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
            onChanged: (v) => vm.setIdadeMin(
              v.isEmpty ? null : int.tryParse(v),
            ),
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
            onChanged: (v) => vm.setIdadeMax(
              v.isEmpty ? null : int.tryParse(v),
            ),
          ),
        );

        final cidadeField = Flexible(
          child: DropdownButtonFormField<String>(
            initialValue: vm.cidadeSelecionada,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cidade',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Todas'),
              ),
              ...vm.availableCidades.map(
                (c) => DropdownMenuItem(value: c, child: Text(c)),
              ),
            ],
            onChanged: (v) => vm.setCidade(v),
          ),
        );

        if (isWide) {
          return Row(
            children: [
              idadeMinField,
              const SizedBox(width: 10),
              idadeMaxField,
              const SizedBox(width: 10),
              cidadeField,
            ],
          );
        }

        return Column(
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
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1320),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFF7B7B).withValues(alpha: 0.3),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFF7B7B), size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nenhum servidor encontrado com os filtros selecionados.',
                style: TextStyle(color: Color(0xFFFF7B7B), fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final allSelected = servers.every((s) => s.isSelected);
    final countSelected = servers.where((s) => s.isSelected).length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(color: const Color(0xFF3ECF8E).withValues(alpha: 0.15)),
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
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                // Masculino
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: servers.where((s) => s.genero == 'Masculino').every((s) => s.isSelected) &&
                             servers.any((s) => s.genero == 'Masculino'),
                      onChanged: servers.any((s) => s.genero == 'Masculino')
                          ? (val) => vm.toggleGenderSelection('Masculino', val ?? false)
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
                      value: servers.where((s) => s.genero == 'Feminino').every((s) => s.isSelected) &&
                             servers.any((s) => s.genero == 'Feminino'),
                      onChanged: servers.any((s) => s.genero == 'Feminino')
                          ? (val) => vm.toggleGenderSelection('Feminino', val ?? false)
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
        separatorBuilder: (_, _) => const Divider(height: 8, thickness: 0.3),
        itemBuilder: (context, index) {
          final server = servers[index];
          final parcs = server.parcelasFormatadas;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 0),
            child: Row(
              children: [
                Checkbox(
                  value: server.isSelected,
                  onChanged: (val) => vm.toggleServerSelection(server, val ?? false),
                  activeColor: const Color(0xFF3ECF8E),
                ),
                const Icon(Icons.person_outline_rounded,
                    size: 18, color: Color(0xFFD4AF37)),
                const SizedBox(width: 8),
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
                const SizedBox(width: 6),
                Text(
                  '${parcs.length} parc.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8891A4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  server.municipio,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC3CAD7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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

// ============================================================
// COLUNA DIREITA
// ============================================================

class _RightColumn extends StatelessWidget {
  const _RightColumn({required this.vm});

  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (vm.feedbackMessage != null) ...[
          _FeedbackBanner(message: vm.feedbackMessage!),
          const SizedBox(height: 16),
        ],
        SectionCard(
          title: 'Previa final',
          subtitle: 'Texto renderizado apos substituir as variaveis.',
          icon: Icons.preview_rounded,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 220),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141821),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.32),
              ),
            ),
            child: SelectableText(
              vm.preview.isEmpty
                  ? 'A previa das mensagens vai aparecer aqui.'
                  : vm.preview,
              style: const TextStyle(height: 1.45),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Resultado de envios',
          subtitle: '${vm.sendResults.length} registro(s)',
          icon: Icons.checklist_rounded,
          child: ResultList(results: vm.sendResults),
        ),
      ],
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
