class AppConstants {
  static const String baseUrl = 'http://localhost:50010';
  static const String apiKey = 'f0Y69k2b5yQWWtmLUs40UVtFWWBIhuWA';
  static const String instanceName = 'money';
  static const String integration = 'WHATSAPP-BAILEYS';
  static const Duration connectionPollInterval = Duration(seconds: 5);
  static const int defaultPresenceDelayMs = 1200;
  static const int minIntervalSeconds = 12;
  static const int maxIntervalSeconds = 25;

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
