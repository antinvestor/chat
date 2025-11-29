import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'app/router.dart';
import 'core/db/database.dart';
import 'core/sync/sync_engine.dart';
import 'core/sync/background_sync_task.dart';

/// Background task callback - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[Workmanager] Executing task: $task');
    
    try {
      // Run background sync
      final success = await BackgroundSyncTask.run();
      print('[Workmanager] Task completed: $success');
      return success;
    } catch (e) {
      print('[Workmanager] Task failed: $e');
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  await AppDatabase.instance.database;

  // Initialize workmanager
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: kDebugMode,
  );

  // Register periodic background sync (15 minutes)
  await Workmanager().registerPeriodicTask(
    'background-sync',
    'backgroundSync',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  print('[Main] Registered background sync task');

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Start sync engine
    ref.read(syncEngineProvider).start();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: 'AntInvestor Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
