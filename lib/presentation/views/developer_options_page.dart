import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config_controller.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Base URL invalida. Informe uma porta (ex: 50010) ou uma URL completa.',
            ),
          ),
        );
      }
      setState(() => _isSaving = false);
      return;
    }

    _baseUrlController.text = config.baseUrl;
    await connectionVm.initialize();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Base URL atualizada para: ${config.baseUrl}')),
      );
    }

    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Opcoes do desenvolvedor')),
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
                child: Card(
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
                          'Informe manualmente a base URL usada nas requisicoes.\n'
                          'Voce pode digitar apenas a porta ngrok/local (ex: 50010) '
                          'ou uma URL completa.',
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _baseUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Base URL / Porta ngrok',
                            hintText:
                                'http://localhost:51062 ou https://abc.ngrok-free.app',
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
