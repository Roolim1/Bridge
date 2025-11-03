import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;

class StartupService {
  static final StartupService _instance = StartupService._internal();
  static Future<StartupService> get instance async {
    await _instance._init(); // Ensure it's initialized
    return _instance;
  }

  StartupService._internal(); // Private constructor

  late final LaunchAtStartup _launchAtStartup;
  late final PackageInfo _packageInfo;

  bool _isInitialized = false;

  Future<void> _init() async {
    // Prevent re-initialization
    if (_isInitialized) return;

    _packageInfo = await PackageInfo.fromPlatform();

    _launchAtStartup = LaunchAtStartup.instance;

    // --- FIX: Removed 'await' as setup() is a void function ---
    _launchAtStartup.setup(
      appName: _packageInfo.appName,
      packageName: _packageInfo.packageName,
      appPath: Platform.resolvedExecutable,
      args: [Platform.isWindows ? '--hidden' : 'hidden'],
    );
    // --- END OF FIX ---

    _isInitialized = true;
  }

  Future<bool> get isEnabled async {
    if (!_isInitialized) await _init();
    return _launchAtStartup.isEnabled();
  }

  Future<void> enable() async {
    if (!_isInitialized) await _init();
    await _launchAtStartup.enable();
  }

  Future<void> disable() async {
    if (!_isInitialized) await _init();
    await _launchAtStartup.disable();
  }

  static String get hiddenArg => Platform.isWindows ? '--hidden' : 'hidden';
}

