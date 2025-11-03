import 'dart:async';
import 'package:universal_io/io.dart'; // <-- ADDED for Platform
import 'dart:ui';

import 'package:bridge/file_transfer_service.dart'; // Our file transfer logic
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart'; // To open files
import 'package:nsd/nsd.dart' as nsd; // <-- ADDED for Network Registration

// Notification plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

/// Sets up the background service
Future<void> initializeService() async {
// ... existing code ...
// (No changes needed in this function)
// ... existing code ...
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
// ... existing code ...
// (No changes needed in this function)
// ... existing code ...
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  HttpServer? server; // To hold the server instance
  nsd.Registration? registration; // <-- ADDED: To hold the registration

  // --- START: Helper functions for NSD ---
  /// Register this device on the network via NSD
  Future<void> registerService() async {
    if (registration != null) {
      await unregisterService(); // Unregister old one if any
    }
    try {
      String deviceName = Platform.localHostname;

      registration = await nsd.register(nsd.Service(
        name: 'Bridge ($deviceName)', // e.g., "Bridge (My-Android)"
        type: '_bridge._tcp',
        port: 8080,
      ));
      print("✅ Background Service Registered: 'Bridge ($deviceName)'");
    } catch (e) {
      print("Background Service registration error: $e");
    }
  }

  /// Unregister this device from the network
  Future<void> unregisterService() async {
    if (registration != null) {
      try {
        await nsd.unregister(registration!);
        print("⭕ Background Service Unregistered.");
      } catch (e) {
        print("Background Service unregister error: $e");
      }
      registration = null;
    }
  }
  // --- END: Helper functions for NSD ---


  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: notificationTapBackground,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // Initial notification setup
  if (service is AndroidServiceInstance) {
// ... existing code ...
  }

  // Listener to stop the service
  service.on('stopService').listen((event) {
    unregisterService(); // <-- ADDED: Unregister on stop
    server?.close(force: true); // Close the server
    service.stopSelf();
  });

  try {
    final localIp = await FileTransferService.getLocalIp();
// ... existing code ...
    if (service is AndroidServiceInstance) {
// ... existing code ...
    }

    // The server instance is returned from `startReceiverServer`
    server = await FileTransferService.startReceiverServer(
          (String filePath, String fileName) async {
// ... existing code ...
// (No changes to this callback)
// ... existing code ...
      },
    );

    // --- FIX: Register the service as soon as it starts ---
    await registerService();
    // --- END OF FIX ---

  } catch (e) {
// ... existing code ...
  }

  // Periodic check to keep service alive
  Timer.periodic(const Duration(seconds: 10), (timer) async {
// ... existing code ...
// (No changes to this timer)
// ... existing code ...
  });
}
