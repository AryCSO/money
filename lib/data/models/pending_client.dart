/// Representa um cliente que respondeu a um disparo e ainda aguarda retorno.
///
/// Alimenta o card "Clientes Pendentes" da tela inicial. Um cliente é
/// considerado pendente quando a última mensagem da conversa veio dele
/// (direção `recebida`) e ainda não houve um envio nosso depois disso.
class PendingClient {
  PendingClient({
    required this.phone,
    required this.sendTarget,
    required this.name,
    required this.genero,
    required this.lastMessage,
    required this.lastReceivedAt,
    this.isSelected = false,
  });

  /// Telefone normalizado (chave da conversa, ex.: 55DDDNUMERO).
  final String phone;

  /// Melhor destino conhecido para o envio (DESTINO_ENVIO salvo na conversa).
  /// Pode ser vazio — nesse caso o serviço de envio resolve a partir do chat.
  final String sendTarget;

  /// Primeiro nome do contato (de pushName/ENVIOS).
  final String name;

  /// 'Masculino', 'Feminino' ou 'Indefinido'.
  final String genero;

  /// Prévia da última mensagem recebida do cliente.
  final String lastMessage;

  /// Quando o cliente respondeu pela última vez.
  final DateTime? lastReceivedAt;

  /// Marcação na UI (seleção manual ou por gênero).
  bool isSelected;

  bool get isMasculino => genero == 'Masculino';
  bool get isFeminino => genero == 'Feminino';
}
