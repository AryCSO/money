import '../../data/models/qr_code_response.dart';
import '../repositories/evolution_repository.dart';

class GetQrCodeUseCase {
  GetQrCodeUseCase(this._repository);

  final EvolutionRepository _repository;

  Future<QrCodeResponse> call() => _repository.getQrCode();
}
