/// Metadados de uma planilha do Google Drive do usuário.
class GoogleSpreadsheetFile {
  const GoogleSpreadsheetFile({
    required this.id,
    required this.name,
    required this.isNativeSheet,
    this.modifiedTime,
  });

  final String id;
  final String name;

  /// `true` para Google Sheets nativo; `false` para `.xlsx` armazenado no Drive.
  final bool isNativeSheet;

  final DateTime? modifiedTime;
}
