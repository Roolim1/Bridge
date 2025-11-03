import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:bridge/file_transfer_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:bridge/startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart'; // <-- FEATURE 2: For save path
import 'package:file_picker/file_picker.dart'; // <-- FEATURE 2: For directory picker
import 'package:archive/archive_io.dart'; // <-- FEATURE 1: For unzipping
import 'package:flutter/foundation.dart'; // <-- FEATURE 1: For compute
import 'package:path/path.dart' as p; // <-- FEATURE 1: For path manipulation

class ServerProvider with ChangeNotifier {
  HttpServer? _server;
  String? _localIp;
  bool _isRunning = false;
  final List<String> _receivedFiles = [];

  nsd.Registration? _registration;

  final StartupService _startupService;
  bool _runOnStartup = true;

  // --- FEATURE 2: Custom Save Path ---
  static const String _savePathKey = 'custom_save_path';
  String? _customSavePath;
  String get savePath {
    if (_customSavePath != null && _customSavePath!.isNotEmpty) {
      return _customSavePath!;
    }
    return "Default (Downloads/Bridge)";
  }
  // --- END OF FEATURE 2 ---

  bool get isRunning => _isRunning;
  String? get localIp => _localIp;
  List<String> get receivedFiles => _receivedFiles;
  bool get runOnStartup => _runOnStartup;

  ServerProvider({required StartupService startupService})
      : _startupService = startupService {
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      _runOnStartup = await _startupService.isEnabled;

      // --- FEATURE 2: Load custom save path ---
      final prefs = await SharedPreferences.getInstance();
      _customSavePath = prefs.getString(_savePathKey);
      // --- END OF FEATURE 2 ---

      notifyListeners();
    } catch (e) {
      print("Error initializing startup service: $e");
    }

    startServer();
  }

  Future<void> startServer() async {
    if (_isRunning) return;

    try {
      _localIp = await FileTransferService.getLocalIp();

      _server = await FileTransferService.startReceiverServer(
              (String filePath, String fileName) async {
            // --- FEATURE 1: Check for zip files (folders) ---
            if (fileName.endsWith('.zip')) {
              final folderName = p.basenameWithoutExtension(fileName);
              _receivedFiles.add('Folder: $folderName'); // Add to list
              notifyListeners();

              try {
                // --- FIX: Naya folder path banayein (e.g., .../Bridge/MyGame) ---
                final String extractPath = p.join(p.dirname(filePath), folderName);
                // --- END OF FIX ---

                // Unzip in an isolate
                // Naya 'extractPath' isolate ko pass karein
                final params = {'filePath': filePath, 'extractPath': extractPath};
                await compute(_unzipFile, params);
                print('Folder extracted into: $extractPath');
              } catch (e) {
                print('Error unzipping file: $e');
                // Add error to list?
              }
            } else {
              // --- Old file logic ---
              _receivedFiles.add('File: $fileName');
              notifyListeners();
              try {
                final result = await OpenFilex.open(filePath);
                print('OpenFilex result: ${result.message}');
              } catch (e) {
                print('Error opening file: $e');
              }
            }
            // --- END OF FEATURE 1 ---
          });

      _isRunning = true;
      print("Server started successfully at $_localIp");
      _registerService();
    } catch (e) {
      _localIp = "Error: ${e.toString()}";
      print("Failed to start server: $e");
    }
    notifyListeners();
  }

  Future<void> stopServer() async {
    if (!_isRunning) return;

    await _unregisterService();
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    _localIp = null;
    print("⭕ Server stopped.");
    notifyListeners();
  }

  Future<void> _registerService() async {
    if (_registration != null) {
      await _unregisterService();
    }
    try {
      String deviceName = Platform.localHostname;
      _registration = await nsd.register(nsd.Service(
        name: 'Bridge ($deviceName)',
        type: '_bridge._tcp',
        port: 8080,
      ));
      print("✅ Service registered on network: 'Bridge ($deviceName)'");
    } catch (e) {
      print("Error registering service: $e");
    }
  }

  Future<void> _unregisterService() async {
    if (_registration != null) {
      try {
        await nsd.unregister(_registration!);
        print("⭕ Service unregistered from network.");
      } catch (e) {
        print("Error unregistering service: $e");
      }
      _registration = null;
    }
  }

  Future<void> setRunOnStartup(bool value) async {
    _runOnStartup = value;
    try {
      if (value) {
        await _startupService.enable();
      } else {
        await _startupService.disable();
      }
    } catch (e) {
      print("Error setting startup preference: $e");
    }
    notifyListeners();
  }

  // --- FEATURE 2: Methods to change save path ---
  Future<void> setCustomSavePath() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && path.isNotEmpty) {
      _customSavePath = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savePathKey, path);
      notifyListeners();
    }
  }

  Future<void> clearCustomSavePath() async {
    _customSavePath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savePathKey);
    notifyListeners();
  }
  // --- END OF FEATURE 2 ---

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}

// --- FEATURE 1: Helper function for unzipping in an isolate ---
void _unzipFile(Map<String, String> params) {
  final String filePath = params['filePath']!;
  final String extractPath = params['extractPath']!;
  final file = File(filePath);

  try {
    // Read the Zip file from disk.
    final bytes = file.readAsBytesSync();
    // Decode the Zip file
    final archive = ZipDecoder().decodeBytes(bytes);

    // Extract the contents of the Zip archive to disk.
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('$extractPath/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        // Handle directories
        Directory('$extractPath/$filename').createSync(recursive: true);
      }
    }
    print('Unzip complete. Deleting zip file.');
    // Delete the zip file after extraction
    file.deleteSync();
  } catch (e) {
    print('Error unzipping in isolate: $e');
    // Re-throw?
  }
}
// --- END OF FEATURE 1 ---
