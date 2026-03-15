class TemplateVariableData {
  final String phone;
  final String nome;
  final String posi;
  final String banco;
  final String parc1;
  final String parc2;
  final String parc3;
  final String parc4;
  final String parc5;

  const TemplateVariableData({
    required this.phone,
    required this.nome,
    required this.posi,
    required this.banco,
    required this.parc1,
    required this.parc2,
    required this.parc3,
    required this.parc4,
    required this.parc5,
  });

  factory TemplateVariableData.empty() {
    return const TemplateVariableData(
      phone: '',
      nome: '',
      posi: '',
      banco: '',
      parc1: '',
      parc2: '',
      parc3: '',
      parc4: '',
      parc5: '',
    );
  }

  TemplateVariableData copyWith({
    String? phone,
    String? nome,
    String? posi,
    String? banco,
    String? parc1,
    String? parc2,
    String? parc3,
    String? parc4,
    String? parc5,
  }) {
    return TemplateVariableData(
      phone: phone ?? this.phone,
      nome: nome ?? this.nome,
      posi: posi ?? this.posi,
      banco: banco ?? this.banco,
      parc1: parc1 ?? this.parc1,
      parc2: parc2 ?? this.parc2,
      parc3: parc3 ?? this.parc3,
      parc4: parc4 ?? this.parc4,
      parc5: parc5 ?? this.parc5,
    );
  }
}
