import 'package:money/data/datasources/database_service.dart';

Future<void> main() async {
  final service = DatabaseService.instance;
  await service.database;
  final contacts = await service.getChatContacts();
  print('firebird_smoke_ok contacts=${contacts.length}');
  await service.close();
}
