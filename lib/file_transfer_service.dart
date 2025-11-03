import 'package:universal_io/io.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // <-- FEATURE 2: For save path

class FileTransferService {
  static Future<String> getLocalIp() async {
    List<String> wifi192Ips = [];
    List<String> ethernet192Ips = [];
    List<String> other192Ips = [];
    List<String> wifi10Ips = [];
    List<String> ethernet10Ips = [];
    List<String> other10Ips = [];
    List<String> wifi172Ips = [];
    List<String> ethernet172Ips = [];
    List<String> other172Ips = [];
    List<String> otherAllIps = [];

    try {
      for (var interface in await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4)) {
        String ip = interface.addresses.first.address;
        String name = interface.name.toLowerCase();
        bool isWifi = name.contains('wi') || name.contains('wl');
        bool isEthernet = name.contains('eth');

        if (ip.startsWith('192.168.')) {
          if (isWifi) wifi192Ips.add(ip);
          else if (isEthernet) ethernet192Ips.add(ip);
          else other192Ips.add(ip);
        } else if (ip.startsWith('10.')) {
          if (isWifi) wifi10Ips.add(ip);
          else if (isEthernet) ethernet10Ips.add(ip);
          else other10Ips.add(ip);
        } else if (ip.startsWith('172.')) {
          if (isWifi) wifi172Ips.add(ip);
          else if (isEthernet) ethernet172Ips.add(ip);
          else other172Ips.add(ip);
        } else {
          otherAllIps.add(ip);
        }
      }
    } catch (e) {
      print("Error getting local IP: $e");
      throw Exception("Could not find network interfaces.");
    }

    if (wifi192Ips.isNotEmpty) return wifi192Ips.first;
    if (ethernet192Ips.isNotEmpty) return ethernet192Ips.first;
    if (other192Ips.isNotEmpty) return other192Ips.first;
    if (wifi10Ips.isNotEmpty) return wifi10Ips.first;
    if (ethernet10Ips.isNotEmpty) return ethernet10Ips.first;
    if (other10Ips.isNotEmpty) return other10Ips.first;
    if (wifi172Ips.isNotEmpty) return wifi172Ips.first;
    if (ethernet172Ips.isNotEmpty) return ethernet172Ips.first;
    if (other172Ips.isNotEmpty) return other172Ips.first;
    if (otherAllIps.isNotEmpty) {
      return otherAllIps.first;
    }

    throw Exception("Could not find a valid local IP address.");
  }

  static Future<List<String>> getAllLocalIps() async {
    final List<String> allIps = [];
    try {
      for (var interface in await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4)) {
        allIps.add(interface.addresses.first.address);
      }
    } catch (e) {
      print("Error getting all local IPs: $e");
    }
    return allIps;
  }

  static Future<HttpServer> startReceiverServer(
      Function(String filePath, String fileName) onFileReceived) async {
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      print('Receiver running at: ${server.address.address}:${server.port}');
    } catch (e) {
      print("Failed to start server: $e");
      throw Exception("Server failed to start: $e");
    }

    _listenForRequests(server, onFileReceived);
    return server;
  }

  // --- FEATURE 2: Updated _listenForRequests ---
  static void _listenForRequests(HttpServer server,
      Function(String filePath, String fileName) onFileReceived) async {
    await for (HttpRequest request in server) {
      if (request.method == 'POST') {
        String? fileName;
        final header = request.headers.value('file-name');
        if (header != null) {
          fileName = Uri.decodeComponent(header);
        }
        fileName ??=
        'received_file_${DateTime.now().millisecondsSinceEpoch}.dat';

        print("Receiving file: $fileName");

        try {
          // --- START: Custom Save Path Logic ---
          final prefs = await SharedPreferences.getInstance();
          final customSavePath = prefs.getString('custom_save_path');

          final Directory saveDir;

          if (customSavePath != null && customSavePath.isNotEmpty) {
            // 1. User has set a custom path
            saveDir = Directory(customSavePath);
          } else {
            // 2. Use the default path (Downloads/Bridge)
            final downloadsDir = await getDownloadsDirectory();
            if (downloadsDir == null) {
              throw Exception("Could not access downloads directory.");
            }
            saveDir = Directory('${downloadsDir.path}/Bridge');
          }

          // Ensure the save directory exists
          if (!await saveDir.exists()) {
            await saveDir.create(recursive: true);
            print('Created directory at: ${saveDir.path}');
          }
          // --- END: Custom Save Path Logic ---

          // 3. Define the final file path
          final filePath = '${saveDir.path}/$fileName';
          final file = File(filePath);

          // 4. Write the file
          final IOSink fileStream = file.openWrite();
          await for (final data in request) {
            fileStream.add(data);
          }
          await fileStream.close();

          print("File saved at: $filePath");
          // 5. Trigger the callback
          onFileReceived(filePath, fileName);

          request.response
            ..statusCode = HttpStatus.ok
            ..write('File received successfully')
            ..close();
        } catch (e) {
          print("Error saving file: $e");
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Error saving file: $e')
            ..close();
        }
      } else {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..close();
      }
    }
  }
  // --- END OF FEATURE 2 ---

  static Future<void> sendFile(String receiverIp, File file, String fileName,
      Function(double) onProgress) async {
    final uri = Uri.parse('http://$receiverIp:8080');
    final client = HttpClient();

    try {
      final req = await client.postUrl(uri);
      final fileSize = await file.length();
      int bytesSent = 0;

      req.headers.add('file-name', Uri.encodeComponent(fileName));
      req.headers.contentType = ContentType.binary;
      req.contentLength = fileSize;

      final stream = file.openRead();

      await stream.listen(
            (List<int> data) {
          bytesSent += data.length;
          final progress = bytesSent / fileSize;
          onProgress(progress);
          req.add(data);
        },
        onDone: () {
          print("File stream upload complete.");
        },
        onError: (e, stackTrace) {
          print("Error sending file stream: $e");
          onProgress(-1.0);
          req.abort();
        },
        cancelOnError: true,
      ).asFuture();

      final response = await req.close();

      if (response.statusCode == HttpStatus.ok) {
        onProgress(1.0);
        print("File sent successfully.");
      } else {
        final responseBody = await response.transform(utf8.decoder).join();
        print(
            "Server error: ${response.statusCode} ${response.reasonPhrase}. Body: $responseBody");
        onProgress(-1.0);
        throw Exception(
            "Receiver error (${response.statusCode}): $responseBody");
      }
    } catch (e) {
      print("HttpClient connection error: $e");
      onProgress(-1.0);
      throw Exception("Failed to send file: ${e.toString()}");
    } finally {
      client.close();
    }
  }
}
