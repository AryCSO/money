import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/pending_client.dart';
import '../viewmodels/pending_clients_viewmodel.dart';

/// Card da tela inicial que resume os clientes que responderam a um disparo
/// e ainda aguardam retorno. O botão "Ver" abre um modal com duas seções:
/// (1) seleção do modelo a disparar e (2) lista de clientes para responder.
class PendingClientsCard extends StatefulWidget {
  const PendingClientsCard({super.key});

  @override
  State<PendingClientsCard> createState() => _PendingClientsCardState();
}

class _PendingClientsCardState extends State<PendingClientsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PendingClientsViewModel>().loadPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PendingClientsViewModel>();
    final count = vm.pendingCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: count > 0
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.mark_chat_unread_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clientes Pendentes',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count > 0
                      ? '$count cliente(s) responderam e aguardam retorno'
                      : 'Nenhum cliente aguardando retorno',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                count.toString(),
                style: GoogleFonts.inter(
                  color: AppColors.warning,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: () => _openModal(context, vm),
            icon: const Icon(Icons.visibility_rounded, size: 16),
            label: Text(
              'Ver',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _openModal(BuildContext context, PendingClientsViewModel vm) {
    vm.loadAll();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: const _PendingClientsModal(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
//  MODAL — 2 SEÇÕES
// ══════════════════════════════════════════════════════════

class _PendingClientsModal extends StatelessWidget {
  const _PendingClientsModal();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PendingClientsViewModel>();

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModalHeader(vm: vm),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: vm.isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 720;
                        final models = _ModelSection(vm: vm);
                        final clients = _ClientsSection(vm: vm);

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 320, child: models),
                              const VerticalDivider(
                                width: 1,
                                color: AppColors.border,
                              ),
                              Expanded(child: clients),
                            ],
                          );
                        }
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(height: 280, child: models),
                              const Divider(height: 1, color: AppColors.border),
                              SizedBox(height: 360, child: clients),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: AppColors.border),
            _ModalFooter(vm: vm),
          ],
        ),
      ),
    );
  }
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.vm});
  final PendingClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.mark_chat_unread_rounded,
              color: AppColors.warning,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clientes Pendentes',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Escolha o modelo e os clientes para responder agora',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: vm.isLoading ? null : vm.loadAll,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: AppColors.textMuted,
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

// ── SEÇÃO 1 — SELEÇÃO DE MODELO ──
class _ModelSection extends StatelessWidget {
  const _ModelSection({required this.vm});
  final PendingClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: _SectionTitle(
            icon: Icons.description_rounded,
            title: 'Modelo de envio',
            subtitle: 'Qual mensagem será disparada',
          ),
        ),
        Expanded(
          child: vm.models.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Nenhum modelo disponível. Crie um modelo na aba Campanhas.',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: vm.models.length,
                  itemBuilder: (_, i) {
                    final model = vm.models[i];
                    final selected = model.id == vm.selectedModelId;
                    return _ModelTile(
                      model: model,
                      selected: selected,
                      onTap: () => vm.selectModel(model.id),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: TextField(
            controller: vm.bancoController,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Banco (token {BANCO})',
              hintText: 'Opcional',
              labelStyle: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final MessageModelOption model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: selected ? AppColors.primaryLight : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${model.messages.length} mensagem(ns)',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SEÇÃO 2 — CLIENTES QUE RESPONDERAM ──
class _ClientsSection extends StatelessWidget {
  const _ClientsSection({required this.vm});
  final PendingClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: _SectionTitle(
            icon: Icons.groups_rounded,
            title: 'Clientes que responderam',
            subtitle: '${vm.selectedCount}/${vm.pendingCount} selecionados',
          ),
        ),
        // Seleção por gênero (não oculta nomes, apenas marca).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              _SelectChip(
                label: 'Todos',
                icon: Icons.people_rounded,
                onTap: () => vm.selectByGender('todos'),
              ),
              const SizedBox(width: 8),
              _SelectChip(
                label: 'Homens',
                icon: Icons.male_rounded,
                onTap: () => vm.selectByGender('M'),
              ),
              const SizedBox(width: 8),
              _SelectChip(
                label: 'Mulheres',
                icon: Icons.female_rounded,
                onTap: () => vm.selectByGender('F'),
              ),
              const SizedBox(width: 8),
              _SelectChip(
                label: 'Limpar',
                icon: Icons.clear_rounded,
                onTap: () => vm.toggleAll(false),
              ),
            ],
          ),
        ),
        Expanded(
          child: vm.clients.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nenhum cliente respondeu ainda.',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: vm.clients.length,
                  itemBuilder: (_, i) {
                    final client = vm.clients[i];
                    return _ClientRow(
                      client: client,
                      onToggle: (v) => vm.toggleClient(client, v),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.onToggle});
  final PendingClient client;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final isM = client.isMasculino;
    final isF = client.isFeminino;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: client.isSelected,
            onChanged: (v) => onToggle(v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name.isNotEmpty ? client.name : client.phone,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  client.lastMessage,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isM || isF)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                isM ? Icons.male_rounded : Icons.female_rounded,
                size: 16,
                color: isM ? AppColors.info : AppColors.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _ModalFooter extends StatelessWidget {
  const _ModalFooter({required this.vm});
  final PendingClientsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              vm.isSending
                  ? 'Enviando ${vm.sendProgress}/${vm.sendTotal}...'
                  : (vm.feedback ?? ''),
              style: GoogleFonts.inter(
                color: vm.isSending ? AppColors.primaryLight : AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: (vm.isSending || vm.selectedCount == 0)
                ? null
                : vm.sendToSelected,
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
              vm.isSending
                  ? 'Enviando...'
                  : 'Responder ${vm.selectedCount} cliente(s)',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auxiliares ──
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
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
        Icon(icon, size: 16, color: AppColors.primaryLight),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
