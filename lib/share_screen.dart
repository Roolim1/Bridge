import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';
import 'file_transfer_service.dart'; // Aapka file transfer service

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

enum ShareStatus { idle, sending, success, error }

class _ShareScreenState extends State<ShareScreen> {
  static const shareChannel = MethodChannel('app.channel.bridge/share');
  static const String _ipSaveKey = 'last_receiver_ip';

  ShareStatus _status = ShareStatus.idle;
  double _progress = 0.0;
  String _fileName = "Loading...";
  String _statusText = "Initializing...";
  File? _fileToSend;

  @override
  void initState() {
    super.initState();
    // Jaise hi screen load ho, file path le kar sending shuru karein
    _initiateSend();
  }

  Future<void> _initiateSend() async {
    try {
      // 1. Native code se file ka path maangein
      final String? filePath = await shareChannel.invokeMethod('getSharedFilePath');
      if (filePath == null) {
        throw Exception("No file path received from native.");
      }

      _fileToSend = File(filePath);
      final fileName = _fileToSend!.path.split(Platform.pathSeparator).last;

      setState(() {
        _fileName = fileName;
        _statusText = "Waiting for IP...";
      });

      // 2. Saved IP address load karein
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString(_ipSaveKey);

      if (savedIp == null || savedIp.isEmpty) {
        throw Exception("No receiver IP saved in app.");
      }

      setState(() {
        _statusText = "Sending to $savedIp...";
        _status = ShareStatus.sending;
      });

      // 3. File send karein
      await FileTransferService.sendFile(
        savedIp,
        _fileToSend!,
        _fileName,
            (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      // 4. Success
      setState(() {
        _statusText = "File Sent!";
        _status = ShareStatus.success;
      });

      // 2 second baad app band kar dein
      Timer(const Duration(seconds: 2), () {
        SystemNavigator.pop(); // App ko band karein
      });

    } catch (e) {
      // 5. Error
      print("Share Error: $e");
      setState(() {
        _statusText = e.toString().replaceAll("Exception: ", "");
        _status = ShareStatus.error;
      });
      // Error ke case mein 3 second baad band karein
      Timer(const Duration(seconds: 3), () {
        SystemNavigator.pop(); // App ko band karein
      });
    }
  }

  IconData getStatusIcon() {
    switch (_status) {
      case ShareStatus.sending:
        return Icons.upload_file;
      case ShareStatus.success:
        return Icons.check_circle;
      case ShareStatus.error:
        return Icons.error;
      case ShareStatus.idle:
        return Icons.hourglass_empty;
    }
  }

  Color getStatusColor() {
    switch (_status) {
      case ShareStatus.sending:
        return Colors.blueAccent;
      case ShareStatus.success:
        return Colors.greenAccent;
      case ShareStatus.error:
        return Colors.redAccent;
      case ShareStatus.idle:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yeh app ko transparent background dega (agar theme support kare)
    // Lekin hum card ko manually center mein rakhenge
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.1), // Peeche sab blur/dim
      body: Center(
        child: Material(
          color: const Color(0xFF333333), // Dark card background
          borderRadius: BorderRadius.circular(16),
          elevation: 8,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85, // 85% width
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      getStatusIcon(),
                      color: getStatusColor(),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                if (_status == ShareStatus.sending)
                  LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.grey[700],
                    valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                  ),
                if (_status == ShareStatus.success)
                  LinearProgressIndicator(
                    value: 1.0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.grey[700],
                    valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                  ),
                if (_status == ShareStatus.error)
                  LinearProgressIndicator(
                    value: 1.0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.grey[700],
                    valueColor: const AlwaysStoppedAnimation(Colors.redAccent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
