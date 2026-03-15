import '../repositories/evolution_repository.dart';

class EnsureMoneyInstanceUseCase {
  EnsureMoneyInstanceUseCase(this._repository);

  final EvolutionRepository _repository;

  Future<void> call() => _repository.ensureMoneyInstance();
}
