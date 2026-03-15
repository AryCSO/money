class QrCodeResponse {
  final String pairingCode;
  final String code;
  final String base64;
  final int count;

  const QrCodeResponse({
    required this.pairingCode,
    required this.code,
    required this.base64,
    required this.count,
  });

  factory QrCodeResponse.fromJson(Map<String, dynamic> json) {
    return QrCodeResponse(
      pairingCode: (json['pairingCode'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      base64: (json['base64'] ?? '').toString(),
      count: int.tryParse((json['count'] ?? 0).toString()) ?? 0,
    );
  }
}
