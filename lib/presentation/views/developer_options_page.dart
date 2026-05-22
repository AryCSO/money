import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/anti_ban_controller.dart';
import '../../core/config/app_config_controller.dart';
import '../../core/config/window_behavior_controller.dart';
import '../../core/utils/app_toast.dart';
import '../viewmodels/connection_viewmodel.dart';

class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  late final TextEditingController _baseUrlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfigController>();
    _baseUrlController = TextEditingController(text: config.baseUrl);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = context.read<AppConfigController>();
    final connectionVm = context.read<ConnectionViewModel>();

    setState(() => _isSaving = true);

    final success = config.updateBaseUrlFromInput(_baseUrlController.text);
    if (!success) {
      if (mounted) {
        AppToast.show(
          context,
          message:
              'Base URL invalida. Informe uma porta (ex: 50010) ou uma URL completa.',
          type: ToastType.warning,
        );
      }
      setState(() => _isSaving = false);
      return;
    }

    _baseUrlController.text = config.baseUrl;
    await connectionVm.initialize();

    if (mounted) {
      AppToast.show(
        context,
        message: 'Base URL atualizada para: ${config.baseUrl}',
        type: ToastType.success,
      );
    }

    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigController>();
    final windowBehavior = context.watch<WindowBehaviorController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF11151E), Color(0xFF0D0E12)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WindowBehaviorCard(controller: windowBehavior),
                    const SizedBox(height: 16),
                    const _AntiBanCard(),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conexao da API',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Porta de acesso do sistema\n',
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _baseUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Base URL / Porta ngrok',
                                hintText:
                                    'http://localhost:52062 ou https://abc.ngrok-free.app',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Base URL atual: ${config.baseUrl}',
                              style: const TextStyle(
                                color: Color(0xFFB8C0CF),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isSaving ? null : _save,
                                icon: _isSaving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded),
                                label: Text(
                                  _isSaving
                                      ? 'Aplicando configuracao...'
                                      : 'Salvar e reconectar',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AntiBanCard extends StatelessWidget {
  const _AntiBanCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AntiBanController>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anti-ban',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Proteções para reduzir risco de banimento em disparos em massa. ',
              style: TextStyle(color: Color(0xFFB8C0CF), fontSize: 12),
            ),
            const SizedBox(height: 14),

            // ── Modo warm-up ──
            const Text(
              'Modo warm-up (teto diário)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<WarmupTier>(
              initialValue: controller.warmupTier,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: WarmupTier.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (value) {
                if (value != null) controller.setWarmupTier(value);
              },
            ),
            const SizedBox(height: 4),
            Text(
              controller.hasDailyCap
                  ? 'Hoje: ${controller.sentToday}/${controller.dailyCap} mensagens'
                  : 'Sem limite de envios diários aplicado.',
              style: const TextStyle(color: Color(0xFFB8C0CF), fontSize: 12),
            ),
            const Divider(height: 28),

            // ── Pausa-café ──
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.coffeeBreakEnabled,
              onChanged: (v) => controller.setCoffeeBreakEnabled(v),
              title: const Text(
                'Pausa-café automática',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'A cada 50 envios consecutivos, descansa 10-15 min para '
                'simular comportamento humano.',
              ),
              secondary: const Icon(Icons.coffee_rounded),
            ),
            const Divider(height: 28),

            // ── Janela horária ──
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.workingHoursEnabled,
              onChanged: (v) => controller.setWorkingHoursEnabled(v),
              title: const Text(
                'Restringir janela horária',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Disparos só entre ${controller.workingHourStart}h e '
                '${controller.workingHourEnd}h. Fora desse '
                'horário, o envio pausa.',
              ),
              secondary: const Icon(Icons.schedule_rounded),
            ),
            if (controller.workingHoursEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _HourField(
                      label: 'Início',
                      value: controller.workingHourStart,
                      onChanged: (v) => controller.setWorkingHours(
                        start: v,
                        end: controller.workingHourEnd,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HourField(
                      label: 'Fim',
                      value: controller.workingHourEnd,
                      onChanged: (v) => controller.setWorkingHours(
                        start: controller.workingHourStart,
                        end: v,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HourField extends StatelessWidget {
  const _HourField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: List.generate(25, (i) => i)
          .map((h) => DropdownMenuItem(value: h, child: Text('${h}h')))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _WindowBehaviorCard extends StatelessWidget {
  const _WindowBehaviorCard({required this.controller});

  final WindowBehaviorController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comportamento da janela',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Controle como o aplicativo se comporta ao ser fechado.',
              style: TextStyle(color: Color(0xFFB8C0CF), fontSize: 12),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.closeToTray,
              onChanged: (v) => controller.setCloseToTray(v),
              title: const Text(
                'Minimizar para a barra de tarefas',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Ao tentar fechar, o sistema é minimizado para a bandeja do sistema '
                'e continua funcionando em segundo plano.'
                'Para sair de verdade, clique com o botao direito no '
                'icone da bandeja e escolha "Sair".',
              ),
              secondary: const Icon(Icons.minimize_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
