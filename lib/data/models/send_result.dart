class SendResult {
  final String phone;
  final bool success;
  final String message;

  const SendResult({
    required this.phone,
    required this.success,
    required this.message,
  });
}
