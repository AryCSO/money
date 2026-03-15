import '../../data/models/instance_connection_state.dart';
import '../repositories/evolution_repository.dart';

class CheckConnectionUseCase {
  CheckConnectionUseCase(this._repository);

  final EvolutionRepository _repository;

  Future<InstanceConnectionState> call() => _repository.getConnectionState();
}
