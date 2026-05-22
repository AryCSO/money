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

  /// O Firebird não está disponível na web.
  bool get isReady => false;

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

  Future<void> markChatRead(String telefone) async {}

  Future<void> updateConversaMediaBytes({
    required String telefone,
    required String mensagemId,
    required Uint8List fileBytes,
    int fileSize = 0,
  }) async {}

  Future<List<Map<String, dynamic>>> getConversationTimeline(
    String telefone, {
    DateTime? visibleFrom,
  }) async => [];

  Future<List<Map<String, dynamic>>> getPendingResponseClients({
    DateTime? visibleFrom,
  }) async => [];

  Future<List<Map<String, dynamic>>> getEnviosHoje() async => [];

  Future<int> salvarModelo({
    required String nome,
    required List<String> mensagens,
  }) async => 0;

  Future<List<Map<String, dynamic>>> listarModelos() async => [];

  Future<void> excluirModelo(int id) async {}

  Future<List<Map<String, dynamic>>> getEnviosPorDia({int days = 7}) async => [];

  Future<List<Map<String, dynamic>>> getMensagensRecebidasPorDia({int days = 7}) async => [];

  Future<Map<String, int>> getEstatisticasGerais() async => {
    'envios_total': 0,
    'respostas_total': 0,
    'envios_hoje': 0,
    'falhas_hoje': 0,
    'respostas_hoje': 0,
  };

  Future<void> close() async {}

  Future<Map<String, dynamic>?> autenticarUsuario({
    required String email,
    required String senha,
  }) async => null;

  Future<Map<String, dynamic>?> carregarUsuarioPorId(int id) async => null;

  Future<bool> emailJaCadastrado(String email) async => false;

  Future<bool> validarTokenAdmin(String token) async => false;

  Future<int> registrarUsuario({
    required String email,
    required String senha,
    required String nomeCompleto,
    required String nomePreferido,
  }) async => 0;
}
