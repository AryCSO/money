// Stub para compilação web — não usa fbdb nem dart:ffi.
// Todos os métodos retornam valores vazios/padrão.
import 'dart:typed_data';

/// Stub do DatabaseService para a plataforma web.
/// O banco de dados Firebird não está disponível na web.
class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  // O getter database não existe no web — stub para compatibilidade.
  Future<void> get database async {}

  Future<int> upsertCliente({
    required String nome,
    required String cargo,
    required String telefone,
    required String ddd,
    required int idade,
    required String municipio,
    required String genero,
    required List<double> parcelas,
  }) async => 0;

  Future<String?> findClientPhoneByName(String name) async => null;

  Future<List<String>> findClientPhoneCandidatesByName(String name) async => [];

  Future<int> registrarEnvio({
    int? clienteId,
    required String telefoneCompleto,
    required String nomeCliente,
    required bool sucesso,
    required String mensagemStatus,
    String mensagemEnviada = '',
    String tipo = 'massa',
  }) async => 0;

  Future<int> countEnviosHojeSucesso() async => 0;

  Future<int> countEnviosHojeFalha() async => 0;

  Future<DateTime> ensureChatVisibleFrom() async => DateTime.now();

  Future<int> registrarMensagem({
    required String telefone,
    String nomeCliente = '',
    String destinoEnvio = '',
    required String direcao,
    required String conteudo,
    String tipoMsg = 'texto',
    String mensagemId = '',
    String arquivoNome = '',
    String arquivoMime = '',
    int arquivoTamanho = 0,
    Uint8List? arquivoDados,
    String mediaUrl = '',
    double? latitude,
    double? longitude,
    String localNome = '',
    String localEndereco = '',
    DateTime? registradoEm,
  }) async => 0;

  Future<List<Map<String, dynamic>>> getConversas(
    String telefone, {
    DateTime? visibleFrom,
  }) async => [];

  Future<List<Map<String, dynamic>>> getChatContacts({
    DateTime? visibleFrom,
  }) async => [];

  Future<List<Map<String, dynamic>>> getConversationTimeline(
    String telefone, {
    DateTime? visibleFrom,
  }) async => [];

  Future<List<Map<String, dynamic>>> getEnviosHoje() async => [];

  Future<int> salvarModelo({
    required String nome,
    required List<String> mensagens,
  }) async => 0;

  Future<List<Map<String, dynamic>>> listarModelos() async => [];

  Future<void> excluirModelo(int id) async {}

  Future<void> close() async {}
}
