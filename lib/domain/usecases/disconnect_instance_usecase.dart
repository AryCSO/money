import '../repositories/evolution_repository.dart';

class DisconnectInstanceUseCase {
  DisconnectInstanceUseCase(this._repository);

  final EvolutionRepository _repository;

  Future<void> call() => _repository.disconnectInstance();
}
