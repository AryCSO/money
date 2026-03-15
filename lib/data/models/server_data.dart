/// Representa um servidor (funcionário) extraído da planilha.
class ServerData {
  final String nome;
  final String cargo;
  final String telefone;
  final String ddd;
  final int idade;
  final String municipio;
  final List<double> parcelas; // top 5, já ordenadas desc
  final bool hasColor; // se a linha tem cor (ignorar)
  final String genero; // Masculino, Feminino, Indefinido
  bool isSelected;

  ServerData({
    required this.nome,
    required this.cargo,
    required this.telefone,
    required this.ddd,
    required this.idade,
    required this.municipio,
    required this.parcelas,
    required this.hasColor,
    required this.genero,
    this.isSelected = true,
  });

  /// Retorna as parcelas formatadas como texto (ex: "R$ 1.234,56")
  List<String> get parcelasFormatadas {
    return parcelas.map((v) {
      final formatted = v.toStringAsFixed(2).replaceAll('.', ',');
      // Adicionar separador de milhar
      final parts = formatted.split(',');
      final intPart = parts[0];
      final decPart = parts[1];
      final buffer = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) {
          buffer.write('.');
        }
        buffer.write(intPart[i]);
      }
      return 'R\$ $buffer,$decPart';
    }).toList();
  }

  /// Verdadeiro se o servidor tiver pelo menos um empréstimo válido
  bool get hasLoans => parcelas.isNotEmpty;
}
