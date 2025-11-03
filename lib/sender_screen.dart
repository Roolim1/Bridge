import 'package:universal_io/io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'file_transfer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import 'dart:ui';
import 'package:path/path.dart' as p; // <-- FEATURE 1: For folder name
import 'package:archive/archive_io.dart'; // <-- FEATURE 1: For zipping
import 'package:flutter/foundation.dart'; // <-- FEATURE 1: For compute
import 'package:path_provider/path_provider.dart'; // <-- FEATURE 1: For temp dir

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  // --- FEATURE 1: Updated state variables ---
  File? _selectedFile;
  Directory? _selectedDirectory;
  String? _selectedItemName;
  // --- END OF FEATURE 1 ---

  final ipController = TextEditingController();
  bool isSending = false;
  double sendProgress = 0.0;
  String sendingStatus = ""; // <-- FEATURE 1: For "Zipping..."
  static const String _ipSaveKey = 'last_receiver_ip';

  bool _isDiscovering = false;
  nsd.Discovery? _discovery;
  VoidCallback? _discoveryListener;
  final List<nsd.Service> _foundServices = [];
  String _myDeviceName = "";

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
    _startDiscovery();
  }

  @override
  void dispose() {
    if (_discovery != null && _discoveryListener != null) {
      _discovery!.removeListener(_discoveryListener!);
    }
    if (_discovery != null) {
      nsd.stopDiscovery(_discovery!);
    }
    ipController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString(_ipSaveKey);
    if (savedIp != null) {
      ipController.text = savedIp;
    }
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipSaveKey, ip);
  }

  Future<void> _startDiscovery() async {
    if (_isDiscovering) return;
    setState(() {
      _isDiscovering = true;
      _foundServices.clear();
    });

    _myDeviceName = Platform.localHostname;
    print("Local device name: $_myDeviceName");

    try {
      _discovery = await nsd.startDiscovery('_bridge._tcp');
      _discoveryListener = () {
        if (mounted) {
          setState(() {
            _foundServices.clear();
            for (final service in _discovery!.services) {
              if (service.type == '_bridge._tcp') {
                _resolveService(service);
              }
            }
          });
        }
      };
      _discovery!.addListener(_discoveryListener!);
    } catch (e) {
      print("Failed to start discovery: $e");
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    }
  }

  Future<void> _resolveService(nsd.Service service) async {
    try {
      final selfServiceName = 'Bridge ($_myDeviceName)';
      if (service.name == selfServiceName) {
        return;
      }

      if (service.host != null) {
        if (mounted) {
          setState(() {
            if (!_foundServices.any((s) => s.name == service.name)) {
              _foundServices.add(service);
            }
          });
        }
        return;
      }

      final resolved = await nsd.resolve(service);
      if (resolved.name != null && resolved.name != selfServiceName) {
        if (mounted) {
          setState(() {
            _foundServices.removeWhere((s) => s.name == resolved.name);
            _foundServices.add(resolved);
          });
        }
      }
    } catch (e) {
      print("Failed to resolve service ${service.name}: $e");
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _selectedDirectory = null; // Clear directory
        _selectedItemName = result.files.single.name;
        isSending = false;
        sendProgress = 0.0;
      });
    }
  }

  // --- FEATURE 1: Add _pickFolder method ---
  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _selectedDirectory = Directory(result);
        _selectedFile = null; // Clear file
        _selectedItemName = p.basename(result); // Get folder name
        isSending = false;
        sendProgress = 0.0;
      });
    }
  }
  // --- END OF FEATURE 1 ---

  // --- FEATURE 1: Renamed to _send() and added folder logic ---
  Future<void> _send() async {
    if ((_selectedFile == null && _selectedDirectory == null) ||
        ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select a file or folder and enter an IP.")),
      );
      return;
    }
    final ipToUse = ipController.text;
    await _saveIp(ipToUse);

    setState(() {
      isSending = true;
      sendProgress = 0.0;
      sendingStatus = "Preparing to send...";
    });

    try {
      // Check if we are sending a directory
      if (_selectedDirectory != null) {
        await _sendFolder(ipToUse);
      } else if (_selectedFile != null) {
        await _sendFile(ipToUse);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sent successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending: ${e.toString()}")),
      );
    } finally {
      setState(() {
        isSending = false;
        sendingStatus = "";
      });
    }
  }
  // --- END OF FEATURE 1 ---

  Future<void> _sendFile(String ip) async {
    await FileTransferService.sendFile(
      ip,
      _selectedFile!,
      _selectedItemName!,
          (progress) {
        setState(() {
          sendProgress = progress;
          sendingStatus = "${(progress * 100).toStringAsFixed(0)}% Sent";
        });
      },
    );
  }

  // --- FEATURE 1: Add _sendFolder method ---
  Future<void> _sendFolder(String ip) async {
    final dir = _selectedDirectory!;
    final folderName = _selectedItemName!;

    setState(() {
      sendingStatus = "Zipping folder...";
      sendProgress = 0; // Show indeterminate
    });

    // 1. Get temp directory
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}/$folderName.zip';
    final zipFile = File(zipPath);

    // 2. Create zip file in an isolate
    final params = {'dirPath': dir.path, 'zipPath': zipPath};
    await compute(_zipDirectory, params);

    if (!await zipFile.exists()) {
      throw Exception("Failed to create zip file.");
    }

    // 3. Send the zip file
    try {
      await FileTransferService.sendFile(
        ip,
        zipFile,
        '$folderName.zip', // Send with .zip extension
            (progress) {
          setState(() {
            sendProgress = progress;
            sendingStatus =
            "Sending folder... ${(progress * 100).toStringAsFixed(0)}%";
          });
        },
      );
    } finally {
      // 4. Delete temp zip file
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  }
  // --- END OF FEATURE 1 ---

  @override
  Widget build(BuildContext context) {
    _foundServices.sort((a, b) => (a.name ?? "").compareTo(b.name ?? ""));

    return Scaffold(
      appBar: AppBar(title: const Text("Sender")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isDiscovering)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 16),
                      Text("Scanning network for receivers..."),
                    ],
                  ),
                ),
              if (_foundServices.isNotEmpty)
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    itemCount: _foundServices.length,
                    itemBuilder: (context, index) {
                      final service = _foundServices[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.devices,
                              color: Colors.blueAccent),
                          title: Text(service.name ?? "Unknown Device"),
                          subtitle:
                          Text("IP: ${service.host ?? 'Resolving...'}"),
                          onTap: () {
                            if (service.host != null) {
                              setState(() {
                                ipController.text = service.host!;
                              });
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Resolving device IP... please wait.")));
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              if (_foundServices.isEmpty && !_isDiscovering)
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Scan Again"),
                  onPressed: _startDiscovery,
                ),
              const SizedBox(height: 16),
              const Divider(),

              // --- FEATURE 1: Buttons for File and Folder ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: const Text("Pick File"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 24),
                    ),
                    onPressed: _pickFile,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text("Pick Folder"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 24),
                    ),
                    onPressed: _pickFolder,
                  ),
                ],
              ),
              // --- END OF FEATURE 1 ---

              const SizedBox(height: 16),
              if (_selectedItemName != null)
                Text(
                  "Selected: $_selectedItemName",
                  style: const TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: "Receiver IP (Auto-filled by scan)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text("Send"), // Renamed from "Send File"
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                  (_selectedFile == null && _selectedDirectory == null ||
                      isSending)
                      ? null
                      : _send, // Use new _send method
                ),
              ),
              const SizedBox(height: 24),
              if (isSending)
                Column(
                  children: [
                    LinearProgressIndicator(
                      // Show indeterminate progress if value is 0 (e.g., during zipping)
                      value: sendProgress > 0 ? sendProgress : null,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sendingStatus, // Use dynamic status text
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- FEATURE 1: Helper function for zipping in an isolate ---
// This must be a top-level function or a static method.
void _zipDirectory(Map<String, String> params) {
  final String dirPath = params['dirPath']!;
  final String zipPath = params['zipPath']!;

  final encoder = ZipFileEncoder();
  encoder.zipDirectory(Directory(dirPath), filename: zipPath, followLinks: false);
  print('Zipping complete: $zipPath');
}
// --- END OF FEATURE 1 ---
