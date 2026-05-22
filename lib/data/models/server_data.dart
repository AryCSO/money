/// Representa um servidor extraido da planilha.
class ServerData {
  /// Primeiro nome — usado no envio (token {NOME}) e na inferencia de genero.
  final String nome;

  /// Nome completo — usado apenas para exibicao/gestao na interface.
  /// O envio continua usando somente o primeiro nome ([nome]).
  final String nomeCompleto;
  final String cargo;
  final String telefone;
  final String ddd;
  final int idade;
  final String municipio;
  final List<double> parcelas;
  final bool hasColor; // reservado para futura deteccao visual
  final String genero;
  bool isSelected;
  bool alreadySent;

  ServerData({
    required this.nome,
    String? nomeCompleto,
    required this.cargo,
    required this.telefone,
    required this.ddd,
    required this.idade,
    required this.municipio,
    required this.parcelas,
    required this.hasColor,
    required this.genero,
    this.isSelected = true,
    this.alreadySent = false,
  }) : nomeCompleto = (nomeCompleto == null || nomeCompleto.trim().isEmpty)
           ? nome
           : nomeCompleto.trim();

  List<String> get parcelasFormatadas {
    return parcelas.map((value) {
      final formatted = value.toStringAsFixed(2).replaceAll('.', ',');
      final parts = formatted.split(',');
      final intPart = parts[0];
      final decPart = parts[1];
      final buffer = StringBuffer();

      for (var i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) {
          buffer.write('.');
        }
        buffer.write(intPart[i]);
      }

      return 'R\$ $buffer,$decPart';
    }).toList();
  }

  bool get hasLoans => parcelas.isNotEmpty;
}
