import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/google_spreadsheet_file.dart';

/// Acessa o Google Drive/Sheets do usuário autenticado para listar e ler
/// planilhas. Trabalha sobre o [AutoRefreshingAuthClient] do [GoogleAuthService].
class GoogleDriveService {
  GoogleDriveService(AutoRefreshingAuthClient client)
    : _drive = drive.DriveApi(client),
      _sheets = sheets.SheetsApi(client);

  final drive.DriveApi _drive;
  final sheets.SheetsApi _sheets;

  static const _sheetMime = 'application/vnd.google-apps.spreadsheet';
  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// E-mail/nome da conta logada (para exibir na interface).
  Future<String?> getUserEmail() async {
    try {
      final about = await _drive.about.get($fields: 'user');
      return about.user?.emailAddress ?? about.user?.displayName;
    } catch (_) {
      return null;
    }
  }

  /// Lista todas as planilhas (Google Sheets + .xlsx) do Drive, mais recentes
  /// primeiro. Pagina automaticamente.
  Future<List<GoogleSpreadsheetFile>> listSpreadsheets() async {
    final files = <GoogleSpreadsheetFile>[];
    String? pageToken;

    do {
      final response = await _drive.files.list(
        q:
            "(mimeType='$_sheetMime' or mimeType='$_xlsxMime') and trashed=false",
        orderBy: 'modifiedTime desc',
        $fields: 'nextPageToken, files(id, name, mimeType, modifiedTime)',
        pageSize: 200,
        spaces: 'drive',
        pageToken: pageToken,
      );

      for (final file in response.files ?? const <drive.File>[]) {
        final id = file.id;
        if (id == null) {
          continue;
        }
        files.add(
          GoogleSpreadsheetFile(
            id: id,
            name: file.name ?? '(sem nome)',
            isNativeSheet: file.mimeType == _sheetMime,
            modifiedTime: file.modifiedTime,
          ),
        );
      }

      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return files;
  }

  /// Lê o conteúdo de uma planilha como linhas (`List<List<dynamic>>`),
  /// no mesmo formato esperado por `SpreadsheetService.parseRows`.
  Future<List<List<dynamic>>> fetchRows(GoogleSpreadsheetFile file) async {
    if (file.isNativeSheet) {
      return _fetchNativeSheetRows(file.id);
    }
    return _fetchXlsxRows(file.id);
  }

  Future<List<List<dynamic>>> _fetchNativeSheetRows(String spreadsheetId) async {
    // Descobre o título da primeira aba para montar o range.
    final meta = await _sheets.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    final title = meta.sheets?.isNotEmpty == true
        ? meta.sheets!.first.properties?.title
        : null;
    if (title == null) {
      return const [];
    }

    final valueRange = await _sheets.spreadsheets.values.get(
      spreadsheetId,
      title,
    );
    final values = valueRange.values;
    if (values == null) {
      return const [];
    }
    return values.map((row) => row.toList()).toList();
  }

  Future<List<List<dynamic>>> _fetchXlsxRows(String fileId) async {
    final media =
        await _drive.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    final bytes = Uint8List.fromList(chunks);

    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    final sheetName = decoder.tables.keys.first;
    final sheet = decoder.tables[sheetName]!;
    return sheet.rows.map((row) => row.toList()).toList();
  }
}
