import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Tetos diários sugeridos para o modo warm-up (anti-ban.md seção 2-3).
enum WarmupTier {
  off,
  conservative, // 80/dia
  moderate, // 200/dia
  aggressive, // 500/dia
}

extension WarmupTierX on WarmupTier {
  int get dailyCap {
    switch (this) {
      case WarmupTier.off:
        return 1 << 30; // sem limite efetivo
      case WarmupTier.conservative:
        return AppConstants.warmupTierConservative;
      case WarmupTier.moderate:
        return AppConstants.warmupTierModerate;
      case WarmupTier.aggressive:
        return AppConstants.warmupTierAggressive;
    }
  }

  String get label {
    switch (this) {
      case WarmupTier.off:
        return 'Sem limite';
      case WarmupTier.conservative:
        return 'Conservador (80/dia)';
      case WarmupTier.moderate:
        return 'Moderado (200/dia)';
      case WarmupTier.aggressive:
        return 'Agressivo (500/dia)';
    }
  }
}

/// Centraliza configurações anti-ban persistidas + contadores diários.
///
/// Responsabilidades:
///  - Janela horária de envio (ex.: 8h-22h)
///  - Pausa-café automática a cada N envios
///  - Teto diário do modo warm-up
///  - Contagem de envios do dia (reset automático na virada de data)
class AntiBanController extends ChangeNotifier {
  static const _kWorkingHoursEnabled = 'antiBan.workingHoursEnabled';
  static const _kWorkingHourStart = 'antiBan.workingHourStart';
  static const _kWorkingHourEnd = 'antiBan.workingHourEnd';
  static const _kCoffeeBreakEnabled = 'antiBan.coffeeBreakEnabled';
  static const _kWarmupTier = 'antiBan.warmupTier';
  static const _kSentCount = 'antiBan.sentCount';
  static const _kSentCountDate = 'antiBan.sentCountDate'; // yyyy-MM-dd

  bool _workingHoursEnabled = false;
  int _workingHourStart = AppConstants.defaultWorkingHourStart;
  int _workingHourEnd = AppConstants.defaultWorkingHourEnd;
  bool _coffeeBreakEnabled = true;
  WarmupTier _warmupTier = WarmupTier.off;

  int _sentToday = 0;
  String _sentCountDate = '';
  bool _initialized = false;

  bool get workingHoursEnabled => _workingHoursEnabled;
  int get workingHourStart => _workingHourStart;
  int get workingHourEnd => _workingHourEnd;
  bool get coffeeBreakEnabled => _coffeeBreakEnabled;
  WarmupTier get warmupTier => _warmupTier;
  int get sentToday {
    _rolloverIfNeeded();
    return _sentToday;
  }

  int get dailyCap => _warmupTier.dailyCap;
  bool get hasDailyCap => _warmupTier != WarmupTier.off;
  int get remainingToday => (dailyCap - sentToday).clamp(0, 1 << 30);
  bool get reachedDailyCap => hasDailyCap && sentToday >= dailyCap;

  bool get initialized => _initialized;

  Future<void> load() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _workingHoursEnabled = prefs.getBool(_kWorkingHoursEnabled) ?? false;
    _workingHourStart =
        prefs.getInt(_kWorkingHourStart) ?? AppConstants.defaultWorkingHourStart;
    _workingHourEnd =
        prefs.getInt(_kWorkingHourEnd) ?? AppConstants.defaultWorkingHourEnd;
    _coffeeBreakEnabled = prefs.getBool(_kCoffeeBreakEnabled) ?? true;
    final tierIndex = prefs.getInt(_kWarmupTier) ?? WarmupTier.off.index;
    _warmupTier = WarmupTier.values[tierIndex.clamp(0, WarmupTier.values.length - 1)];
    _sentToday = prefs.getInt(_kSentCount) ?? 0;
    _sentCountDate = prefs.getString(_kSentCountDate) ?? _todayKey();
    _rolloverIfNeeded();
    _initialized = true;
    notifyListeners();
  }

  Future<void> setWorkingHoursEnabled(bool value) async {
    if (_workingHoursEnabled == value) return;
    _workingHoursEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWorkingHoursEnabled, value);
  }

  Future<void> setWorkingHours({required int start, required int end}) async {
    final normalizedStart = start.clamp(0, 23);
    final normalizedEnd = end.clamp(1, 24);
    if (_workingHourStart == normalizedStart && _workingHourEnd == normalizedEnd) {
      return;
    }
    _workingHourStart = normalizedStart;
    _workingHourEnd = normalizedEnd;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWorkingHourStart, normalizedStart);
    await prefs.setInt(_kWorkingHourEnd, normalizedEnd);
  }

  Future<void> setCoffeeBreakEnabled(bool value) async {
    if (_coffeeBreakEnabled == value) return;
    _coffeeBreakEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCoffeeBreakEnabled, value);
  }

  Future<void> setWarmupTier(WarmupTier tier) async {
    if (_warmupTier == tier) return;
    _warmupTier = tier;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWarmupTier, tier.index);
  }

  /// Incrementa contador diário (chamado após cada envio bem-sucedido).
  Future<void> incrementSentToday() async {
    _rolloverIfNeeded();
    _sentToday++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSentCount, _sentToday);
    await prefs.setString(_kSentCountDate, _sentCountDate);
  }

  /// Verifica se o horário atual está dentro da janela permitida.
  bool isWithinWorkingHours([DateTime? now]) {
    if (!_workingHoursEnabled) return true;
    final n = now ?? DateTime.now();
    final hour = n.hour;
    if (_workingHourStart <= _workingHourEnd) {
      return hour >= _workingHourStart && hour < _workingHourEnd;
    }
    // janela cruzando meia-noite (ex.: 22-6): improvável aqui, mas suportado.
    return hour >= _workingHourStart || hour < _workingHourEnd;
  }

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  void _rolloverIfNeeded() {
    final today = _todayKey();
    if (_sentCountDate != today) {
      _sentToday = 0;
      _sentCountDate = today;
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setInt(_kSentCount, 0);
        await prefs.setString(_kSentCountDate, today);
      });
    }
  }
}
