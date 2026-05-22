class AppConstants {
  static const String baseUrl = 'http://localhost:52062';
  static const String apiKey = 'f0Y69k2b5yQWWtmLUs40UVtFWWBIhuWA';
  static const String instanceName = 'money';
  static const String integration = 'WHATSAPP-BAILEYS';
  static const Duration connectionPollInterval = Duration(seconds: 5);
  static const int defaultPresenceDelayMs = 1200;

  // ── Defaults anti-ban para intervalo entre destinatários ──
  // Recomendação consolidada: 15–45s (ver anti-ban.md, seção 4).
  static const int minIntervalSeconds = 15;
  static const int maxIntervalSeconds = 45;

  // ── Pausa-café (anti-ban.md seção 3) ──
  // A cada N envios consecutivos, descansa entre min/max minutos.
  static const int coffeeBreakEveryMessages = 50;
  static const int coffeeBreakMinMinutes = 10;
  static const int coffeeBreakMaxMinutes = 15;

  // ── Janela horária (anti-ban.md seção 3) ──
  // Default: 8h às 22h no fuso local.
  static const int defaultWorkingHourStart = 8;
  static const int defaultWorkingHourEnd = 22;

  // ── Modo warm-up (anti-ban.md seção 2) ──
  // Tetos diários sugeridos.
  static const int warmupTierConservative = 80;
  static const int warmupTierModerate = 200;
  static const int warmupTierAggressive = 500;

  /// Settings recomendados para a instância Evolution API (Baileys).
  /// Aplicados em `POST /instance/create` e `POST /settings/set/{instance}`.
  static const Map<String, dynamic> antiBanInstanceSettings = {
    'rejectCall': true,
    'msgCall':
        'Olá! No momento não consigo atender chamadas. Pode me enviar uma mensagem aqui?',
    'groupsIgnore': true,
    'alwaysOnline': false,
    'readMessages': true,
    'readStatus': false,
    'syncFullHistory': false,
  };

  static const List<String> supportedTokens = [
    '{NOME}',
    '{POSI}',
    '{BANCO}',
    '{PARC1}',
    '{PARC2}',
    '{PARC3}',
    '{PARC4}',
    '{PARC5}',
  ];
}
