import 'package:flutter/foundation.dart';

import '../../data/datasources/database_service.dart';
import '../widgets/activity_chart.dart';

/// Item de envio recente exibido no dashboard, lido da tabela ENVIOS.
class RecentEnvio {
  const RecentEnvio({
    required this.success,
    required this.phone,
    required this.message,
    required this.sentAt,
  });

  final bool success;
  final String phone;
  final String message;
  final DateTime? sentAt;
}

/// ViewModel que carrega estatísticas reais do banco Firebird
/// para alimentar os gráficos da tela de Overview.
class OverviewViewModel extends ChangeNotifier {
  OverviewViewModel() {
    loadStats();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Reflete o estado real da conexão com o banco Firebird.
  bool get dbReady => DatabaseService.instance.isReady;

  // Dados do gráfico de barras (atividade semanal)
  List<ActivityBarData> _weeklyActivity = [];
  List<ActivityBarData> get weeklyActivity => _weeklyActivity;

  // Dados do gráfico de linha (respostas recebidas por dia)
  List<double> _weeklyResponses = [];
  List<double> get weeklyResponses => _weeklyResponses;

  // Envios recentes persistidos no banco (não a sessão atual)
  List<RecentEnvio> _recentEnvios = [];
  List<RecentEnvio> get recentEnvios => _recentEnvios;

  // Estatísticas gerais do banco
  int _enviosTotal = 0;
  int get enviosTotal => _enviosTotal;

  int _respostasTotal = 0;
  int get respostasTotal => _respostasTotal;

  int _enviosHoje = 0;
  int get enviosHoje => _enviosHoje;

  int _falhasHoje = 0;
  int get falhasHoje => _falhasHoje;

  int _respostasHoje = 0;
  int get respostasHoje => _respostasHoje;

  double get taxaRetorno =>
      _enviosTotal > 0 ? (_respostasTotal / _enviosTotal * 100).clamp(0, 100) : 0;

  Future<void> loadStats() async {
    _isLoading = true;
    notifyListeners();

    try {
      final db = DatabaseService.instance;

      // Carregar dados em paralelo, com timeout duro para nao deixar o
      // dashboard preso caso o Firebird esteja lento ou inacessivel.
      final results = await Future.wait([
        db.getEnviosPorDia(days: 7),
        db.getMensagensRecebidasPorDia(days: 7),
        db.getEstatisticasGerais(),
        db.getEnviosHoje(),
      ]).timeout(const Duration(seconds: 6));

      final enviosPorDia = results[0] as List<Map<String, dynamic>>;
      final respostasPorDia = results[1] as List<Map<String, dynamic>>;
      final stats = results[2] as Map<String, int>;
      final enviosHojeRows = results[3] as List<Map<String, dynamic>>;

      // Montar dados da semana (últimos 7 dias)
      _weeklyActivity = _buildWeeklyActivity(enviosPorDia, respostasPorDia);
      _weeklyResponses = _buildWeeklyResponses(respostasPorDia);

      // Estatísticas gerais
      _enviosTotal = stats['envios_total'] ?? 0;
      _respostasTotal = stats['respostas_total'] ?? 0;
      _enviosHoje = stats['envios_hoje'] ?? 0;
      _falhasHoje = stats['falhas_hoje'] ?? 0;
      _respostasHoje = stats['respostas_hoje'] ?? 0;

      // Lista de envios recentes (persistidos no banco)
      _recentEnvios = enviosHojeRows.take(8).map((row) {
        return RecentEnvio(
          success: _asInt(row['sucesso']) == 1,
          phone: row['telefone_completo']?.toString() ?? '',
          message: (row['mensagem_enviada']?.toString().trim().isNotEmpty == true)
              ? row['mensagem_enviada'].toString()
              : (row['mensagem_status']?.toString() ?? ''),
          sentAt: _parseDate(row['enviado_em']),
        );
      }).toList();
    } catch (e) {
      debugPrint('OverviewViewModel.loadStats erro: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<ActivityBarData> _buildWeeklyActivity(
    List<Map<String, dynamic>> envios,
    List<Map<String, dynamic>> respostas,
  ) {
    final now = DateTime.now();
    final days = <ActivityBarData>[];
    final weekDayLabels = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final label = weekDayLabels[day.weekday % 7];

      double sent = 0;
      double received = 0;

      // Buscar envios do dia
      for (final row in envios) {
        final diaValue = row['dia'];
        final rowDate = _parseDate(diaValue);
        if (rowDate != null && _isSameDay(rowDate, day)) {
          sent = (row['sucesso_count'] ?? row['total'] ?? 0).toDouble();
          break;
        }
      }

      // Buscar respostas do dia
      for (final row in respostas) {
        final diaValue = row['dia'];
        final rowDate = _parseDate(diaValue);
        if (rowDate != null && _isSameDay(rowDate, day)) {
          received = (row['total'] ?? 0).toDouble();
          break;
        }
      }

      days.add(ActivityBarData(label: label, sent: sent, received: received));
    }

    return days;
  }

  List<double> _buildWeeklyResponses(List<Map<String, dynamic>> respostas) {
    final now = DateTime.now();
    final values = <double>[];

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      double count = 0;

      for (final row in respostas) {
        final diaValue = row['dia'];
        final rowDate = _parseDate(diaValue);
        if (rowDate != null && _isSameDay(rowDate, day)) {
          count = (row['total'] ?? 0).toDouble();
          break;
        }
      }

      values.add(count);
    }

    return values;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value.replaceFirst(' ', 'T'))?.toLocal();
    }
    return null;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
