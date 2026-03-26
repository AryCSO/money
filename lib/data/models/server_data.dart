/// Representa um servidor extraido da planilha.
class ServerData {
  final String nome;
  final String cargo;
  final String telefone;
  final String ddd;
  final int idade;
  final String municipio;
  final List<double> parcelas;
  final bool hasColor; // reservado para futura deteccao visual
  final String genero;
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
