import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/database/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbService = DatabaseService();
  await dbService.database;

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(dbService),
      ],
      child: const WinDeployStudioApp(),
    ),
  );
}
