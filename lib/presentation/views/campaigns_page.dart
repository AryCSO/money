import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/server_data.dart';
import '../viewmodels/auto_reply_viewmodel.dart';
import '../viewmodels/template_viewmodel.dart';
import '../widgets/token_chip_list.dart';
import '../widgets/whatsapp_bubble_preview.dart';

class CampaignsPage extends StatefulWidget {
  const CampaignsPage({super.key});

  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemplateViewModel>();

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Tab bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 13.5),
              dividerColor: AppColors.border,
              tabs: const [
                Tab(text: 'Templates & Envio Manual'),
                Tab(text: 'Disparo em Massa'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TemplatesTab(vm: vm),
                _BulkSendTab(vm: vm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  TAB 1 — TEMPLATES & ENVIO MANUAL
// ══════════════════════════════════════════════════════════

class _TemplatesTab extends StatelessWidget {
  const _TemplatesTab({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final editor = _TemplateEditor(vm: vm);
        final preview = _PreviewPanel(vm: vm);

        if (isWide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: editor),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: preview),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              editor,
              const SizedBox(height: 16),
              preview,
            ],
          ),
        );
      },
    );
  }
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({required this.vm});
  final TemplateViewModel vm;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  bool _isTemplatesExpanded = true;

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
        backgroundColor: AppColors.surfaceAlt,
        title: Text(
          'Salvar Modelo',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.inter(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Nome do modelo',
            hintText: 'Ex: Quitação Padrão',
            labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                widget.vm.saveTemplateToDatabase(name);
                Navigator.pop(ctx);
              }
            },
            child: Text('Salvar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Collapsible Templates Section ──
        GestureDetector(
          onTap: () => setState(() => _isTemplatesExpanded = !_isTemplatesExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: AppColors.primaryLight, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Templates e Mensagens',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Configure até 6 mensagens encadeadas',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isTemplatesExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Saved Models Tab ──
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.folder_rounded, size: 16, color: AppColors.primaryLight),
                        const SizedBox(width: 8),
                        Text(
                          'Modelos Salvos',
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13,
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
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (vm.savedModels.isEmpty)
                      Text(
                        'Nenhum modelo salvo ainda.',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: vm.savedModels.map((model) {
                          final name = model['nome']?.toString() ?? 'Sem nome';
                          final id = model['id'] is int ? model['id'] as int : int.tryParse(model['id']?.toString() ?? '') ?? 0;
                          return Chip(
                            label: Text(
                              name,
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                              ),
                            ),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                            deleteIcon: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
                            onDeleted: () => vm.deleteSavedModel(id),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: vm.savedModels.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 6),
                          itemBuilder: (_, i) {
                            final model = vm.savedModels[i];
                            final name = model['nome']?.toString() ?? 'Sem nome';
                            return ActionChip(
                              label: Text(
                                'Carregar "$name"',
                                style: GoogleFonts.inter(fontSize: 11, color: AppColors.primaryLight),
                              ),
                              backgroundColor: AppColors.surfaceAlt,
                              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
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
              const SizedBox(height: 12),
              ...List.generate(6, (i) => _TemplateField(index: i, vm: vm)),
              const SizedBox(height: 12),
              // Save to DB button
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showSaveModelDialog,
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text(
                        'Salvar como Modelo',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.tag_rounded,
                title: 'Variáveis disponíveis',
                subtitle: 'Clique para inserir no template selecionado',
              ),
              const SizedBox(height: 10),
              TokenChipList(tokens: vm.tokensUsed),
              const SizedBox(height: 24),
              _ManualSendCard(vm: vm),
            ],
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _isTemplatesExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}

class _TemplateField extends StatelessWidget {
  const _TemplateField({required this.index, required this.vm});
  final int index;
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    final hasContent = vm.templateControllers[index].text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasContent
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: hasContent
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.border.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.inter(
                          color: hasContent
                              ? AppColors.primaryLight
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mensagem ${index + 1}',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (hasContent)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                ],
              ),
            ),
            TextField(
              controller: vm.templateControllers[index],
              maxLines: 3,
              minLines: 2,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 13.5,
              ),
              decoration: InputDecoration(
                hintText: 'Digite a mensagem ${index + 1}… use {NOME}, {POSI}, {spintax|alternativa}',
                hintStyle: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              ),
              onChanged: (_) => vm.updatePreview(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualSendCard extends StatelessWidget {
  const _ManualSendCard({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.send_rounded,
            title: 'Envio Manual',
            subtitle: 'Envie para um número específico',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: vm.ddiController,
                  decoration: InputDecoration(
                    labelText: 'DDI',
                    hintText: '55',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: vm.dddController,
                  decoration: InputDecoration(
                    labelText: 'DDD',
                    hintText: '11',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: vm.phoneController,
                  decoration: InputDecoration(
                    labelText: 'Número',
                    hintText: '999999999',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: vm.nomeController,
                  decoration: InputDecoration(
                    labelText: 'Nome',
                    hintText: 'João Silva',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: (_) => vm.updatePreview(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: vm.posiController,
                  decoration: InputDecoration(
                    labelText: 'Cargo',
                    hintText: 'Analista',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: (_) => vm.updatePreview(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: vm.bancoController,
                  decoration: InputDecoration(
                    labelText: 'Banco',
                    hintText: 'Bradesco',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: (_) => vm.updatePreview(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: vm.isSending ? null : vm.sendMessages,
              icon: vm.isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                vm.isSending ? 'Enviando...' : 'Enviar agora',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.phone_iphone_rounded,
          title: 'Pré-visualização',
          subtitle: 'Como o destinatário verá',
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B141A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                // Phone header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  color: const Color(0xFF202C33),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(0xFF2A3942),
                        child: Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: Color(0xFF8696A0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vm.nomeController.text.isNotEmpty
                                ? vm.nomeController.text
                                : 'Destinatário',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'online',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF8696A0),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Messages
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: WhatsAppBubblePreview(
                    messages: vm.preview
                        .split('\n\n---\n\n')
                        .where((s) => s.trim().isNotEmpty)
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════
//  TAB 2 — DISPARO EM MASSA
// ══════════════════════════════════════════════════════════

class _BulkSendTab extends StatelessWidget {
  const _BulkSendTab({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final spreadsheet = _SpreadsheetPanel(vm: vm);
        final controls = _BulkControlsPanel(vm: vm);

        if (isWide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: spreadsheet),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: controls),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              spreadsheet,
              const SizedBox(height: 16),
              controls,
            ],
          ),
        );
      },
    );
  }
}

class _SpreadsheetPanel extends StatelessWidget {
  const _SpreadsheetPanel({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.table_chart_rounded,
              title: 'Planilha de Contatos',
              subtitle: 'Importe uma planilha Excel (.xlsx)',
            ),
            const SizedBox(height: 14),
            // Upload button
            _UploadButton(vm: vm),
            if (vm.hasSpreadsheet) ...[
              const SizedBox(height: 16),
              _GenderFilter(vm: vm),
              const SizedBox(height: 10),
              _FiltersCard(vm: vm),
              const SizedBox(height: 16),
              _ContactsPreview(vm: vm),
            ],
          ],
        ),
        // Loading overlay
        if (vm.isLoadingSpreadsheet)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      vm.spreadsheetLoadingMessage,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aguarde...',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: vm.isLoadingSpreadsheet ? null : vm.pickAndLoadSpreadsheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: vm.hasSpreadsheet
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.border,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              vm.hasSpreadsheet
                  ? Icons.check_circle_rounded
                  : Icons.upload_file_rounded,
              size: 32,
              color: vm.hasSpreadsheet ? AppColors.success : AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              vm.hasSpreadsheet
                  ? vm.spreadsheetFileName ?? 'Planilha carregada'
                  : 'Clique para importar planilha',
              style: GoogleFonts.inter(
                color: vm.hasSpreadsheet
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (vm.hasSpreadsheet)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${vm.filteredServers.length} contatos selecionados',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Formatos suportados: .xlsx, .xls',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Filtros',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Idade mín.',
                    hintText: '18',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => vm.setIdadeMin(int.tryParse(v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Idade máx.',
                    hintText: '65',
                    labelStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => vm.setIdadeMax(int.tryParse(v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (vm.availableCidades.isNotEmpty)
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: vm.cidadeSelecionada,
              decoration: InputDecoration(
                labelText: 'Município',
                labelStyle: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              dropdownColor: AppColors.surfaceAlt,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    'Todos',
                    style: GoogleFonts.inter(color: AppColors.textMuted),
                  ),
                ),
                ...vm.availableCidades.map(
                  (c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(c),
                  ),
                ),
              ],
              onChanged: vm.setCidade,
            ),
        ],
      ),
    );
  }
}

class _ContactsPreview extends StatelessWidget {
  const _ContactsPreview({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    final servers = vm.filteredServers;
    final selectedCount = servers.where((s) => s.isSelected).length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  'Contatos importados',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$selectedCount/${servers.length} selecionados',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          // Select/deselect all
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
            child: Row(
              children: [
                Checkbox(
                  value: selectedCount == servers.length && servers.isNotEmpty,
                  tristate: true,
                  onChanged: (val) {
                    vm.toggleAllServers(val == true);
                  },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(
                  'Selecionar todos',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Scrollable list
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 350),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: servers.length,
              itemBuilder: (_, i) => _ContactRow(
                server: servers[i],
                onToggle: (selected) => vm.toggleServerSelection(servers[i], selected),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.server, required this.onToggle});
  final ServerData server;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: server.isSelected,
            onChanged: (val) => onToggle(val ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: server.isSelected
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.border.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                (server.nome.isNotEmpty ? server.nome[0] : '?').toUpperCase(),
                style: GoogleFonts.inter(
                  color: server.isSelected ? AppColors.primaryLight : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.nome,
                  style: GoogleFonts.inter(
                    color: server.isSelected ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${server.ddd} ${server.telefone} • ${server.municipio}',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (server.alreadySent)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: 'Já enviado nos últimos 30 dias',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'enviado',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          if (server.genero == 'Masculino' || server.genero == 'Feminino')
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                server.genero == 'Masculino' ? Icons.male_rounded : Icons.female_rounded,
                size: 16,
                color: server.genero == 'Masculino' ? AppColors.info : AppColors.error,
              ),
            ),
          if (server.idade > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${server.idade}a',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GenderFilter extends StatelessWidget {
  const _GenderFilter({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wc_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Filtrar por Gênero',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _GenderChip(
                label: 'Todos',
                icon: Icons.people_rounded,
                selected: vm.genderFilter == 'todos',
                onTap: () => vm.setGenderFilter('todos'),
              ),
              const SizedBox(width: 8),
              _GenderChip(
                label: 'Homens',
                icon: Icons.male_rounded,
                selected: vm.genderFilter == 'M',
                onTap: () => vm.setGenderFilter('M'),
              ),
              const SizedBox(width: 8),
              _GenderChip(
                label: 'Mulheres',
                icon: Icons.female_rounded,
                selected: vm.genderFilter == 'F',
                onTap: () => vm.setGenderFilter('F'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primaryLight : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: selected ? AppColors.primaryLight : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkControlsPanel extends StatelessWidget {
  const _BulkControlsPanel({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    final autoReplyVm = context.watch<AutoReplyViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.rocket_launch_rounded,
          title: 'Controles de Disparo',
          subtitle: 'Configure intervalos e inicie',
        ),
        const SizedBox(height: 14),
        // Intervalo
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Intervalo entre mensagens',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: vm.minIntervalController,
                      decoration: InputDecoration(
                        labelText: 'Mínimo (s)',
                        labelStyle: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: vm.maxIntervalController,
                      decoration: InputDecoration(
                        labelText: 'Máximo (s)',
                        labelStyle: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Auto-reply toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.reply_all_rounded,
                size: 18,
                color: autoReplyVm.isEnabled
                    ? AppColors.success
                    : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-resposta',
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Responde automaticamente às mensagens recebidas',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: autoReplyVm.isEnabled,
                onChanged: (_) => autoReplyVm.toggle(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Progress
        if (vm.isSending) ...[
          _ProgressCard(vm: vm),
          const SizedBox(height: 12),
        ],
        // Action buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: vm.isSending || !vm.hasSpreadsheet
                    ? null
                    : vm.sendBulkFromSpreadsheet,
                icon: vm.isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 16),
                label: Text(
                  vm.isSending ? 'Disparando...' : 'Iniciar Disparo',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (vm.isSending) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: vm.cancelSending,
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: Text(
                  'Cancelar',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Results
        if (vm.sendResults.isNotEmpty) _ResultsCard(vm: vm),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    final progress = vm.sendTotal > 0
        ? vm.sendProgress / vm.sendTotal
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryLight,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Enviando ${vm.sendProgress} de ${vm.sendTotal}',
                style: GoogleFonts.inter(
                  color: AppColors.primaryLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.vm});
  final TemplateViewModel vm;

  @override
  Widget build(BuildContext context) {
    final success = vm.sendResults.where((r) => r.success).length;
    final failed = vm.sendResults.length - success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Resultados',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _MiniStat(
                value: success.toString(),
                label: 'ok',
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              _MiniStat(
                value: failed.toString(),
                label: 'err',
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: vm.sendResults.length,
              itemBuilder: (_, i) {
                final r = vm.sendResults[vm.sendResults.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        r.success ? Icons.check_circle_rounded : Icons.error_rounded,
                        size: 14,
                        color: r.success ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          r.phone.isNotEmpty ? r.phone : r.message,
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$value $label',
        style: GoogleFonts.inter(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// SHARED SECTION HEADER
// ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
