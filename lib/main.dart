import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bridge/server_provider.dart';
import 'sender_screen.dart';
import 'package:bridge/startup_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';  // ✅ updated API
import 'package:bridge/settings_drawer.dart';

bool isDesktop() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

const String _appId = "com.bridge.app.bridge";

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop()) {
    // Use the package's API
    final single = FlutterSingleInstance();
    bool first = await single.isFirstInstance();

    if (!first) {
      // Another instance already running
      await single.focus();  // bring to front existing instance
      return;
    }
    // Continue: (we could also listen for new arguments, but the package only supports focus())
  }

  final startupService = await StartupService.instance;

  if (isDesktop()) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);

    bool startHidden = args.contains(StartupService.hiddenArg);

    WindowOptions windowOptions = WindowOptions(
      skipTaskbar: startHidden,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startHidden) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
      windowManager.addListener(_MyWindowListener());
    });
  }

  if (Platform.isAndroid) {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => ServerProvider(startupService: startupService),
      child: const FileShareApp(),
    ),
  );
}

class FileShareApp extends StatefulWidget {
  const FileShareApp({super.key});

  @override
  State<FileShareApp> createState() => _FileShareAppState();
}

class _FileShareAppState extends State<FileShareApp> {
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  @override
  void initState() {
    super.initState();
    if (isDesktop()) {
      initSystemTray();
    }
  }

  Future<void> initSystemTray() async {
    final Menu menu = Menu()
      ..buildFrom([
        MenuItemLabel(
          label: 'Show',
          onClicked: (menuItem) {
            windowManager.setSkipTaskbar(false);
            _appWindow.show();
          },
        ),
        MenuItemLabel(
          label: 'Hide',
          onClicked: (menuItem) {
            windowManager.setSkipTaskbar(true);
            _appWindow.hide();
          },
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Quit',
          onClicked: (menuItem) => windowManager.destroy(),
        ),
      ]);

    await _systemTray.initSystemTray(
      iconPath: Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png',
      toolTip: "Bridge File Transfer",
    );

    await _systemTray.setContextMenu(menu);

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.setSkipTaskbar(false);
        _appWindow.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LAN File Share',
      theme: ThemeData.dark(),
      initialRoute: '/',
      routes: {
        '/': (context) => const MainMenu(),
        '/sender': (context) => const SenderScreen(),
      },
    );
  }
}

class _MyWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    windowManager.setSkipTaskbar(true);
    windowManager.hide();
  }

  @override
  void onWindowMinimize() {}

  @override
  void onWindowFocus() {}
}

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final Uri coffeeUri = Uri.parse('https://buymeacoffee.com/ryokcodes');

    Future<void> _launchUrl() async {
      if (!await launchUrl(coffeeUri)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open link')),
          );
        }
      }
    }

    return Consumer<ServerProvider>(
      builder: (context, server, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("LAN File Share"),
            actions: [
              IconButton(
                icon: const Icon(Icons.coffee_outlined),
                tooltip: 'Support the developer',
                onPressed: _launchUrl,
              ),
            ],
          ),
          drawer: SettingsDrawer(server: server),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text("Sender Mode", style: TextStyle(fontSize: 18)),
                    onPressed: () => Navigator.pushNamed(context, '/sender'),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  SwitchListTile(
                    title: const Text("Receiver Service", style: TextStyle(fontSize: 18)),
                    subtitle: Text(server.isRunning ? "Service is active" : "Service is stopped"),
                    value: server.isRunning,
                    onChanged: (bool value) {
                      if (value) {
                        server.startServer();
                      } else {
                        server.stopServer();
                      }
                    },
                  ),
                  if (server.isRunning && server.localIp != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Column(
                        children: [
                          SelectableText(
                            server.localIp!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: server.localIp!.startsWith("Error") ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                          Text(
                            "",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (isDesktop())
                    SwitchListTile(
                      title: const Text("Run on Startup", style: TextStyle(fontSize: 18)),
                      subtitle: Text(server.runOnStartup ? "Enabled" : "Disabled"),
                      value: server.runOnStartup,
                      onChanged: (bool value) {
                        server.setRunOnStartup(value);
                      },
                    ),
                  const SizedBox(height: 20),
                  if (server.receivedFiles.isNotEmpty)
                    const Text("Recently Received:", style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: ListView.builder(
                      itemCount: server.receivedFiles.length,
                      itemBuilder: (context, index) {
                        final reversedIndex = server.receivedFiles.length - 1 - index;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              server.receivedFiles[reversedIndex].startsWith("Folder:")
                                  ? Icons.folder_zip
                                  : Icons.insert_drive_file,
                              color: Colors.greenAccent,
                            ),
                            title: Text(
                              server.receivedFiles[reversedIndex].replaceFirst("Folder: ", ""),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
