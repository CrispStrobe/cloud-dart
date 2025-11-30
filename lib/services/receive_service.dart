// services/receive_service.dart
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'dart:io';

class ReceiveService {
  static StreamSubscription? _intentSubscription;

  static void initialize({
    required Function(List<String>) onFilesReceived,
    required Function(String) onTextReceived,
  }) {
    // Only initialize on mobile platforms
    if (!Platform.isAndroid && !Platform.isIOS) {
      print('⚠️ Receive sharing intent not supported on ${Platform.operatingSystem}');
      return;
    }

    try {
      // For files
      _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> files) {
          if (files.isNotEmpty) {
            final paths = files.map((f) => f.path).toList();
            onFilesReceived(paths);
          }
        },
        onError: (err) {
          print("Error receiving shared files: $err");
        },
      );

      // Get initial media (when app was closed)
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          final paths = files.map((f) => f.path).toList();
          onFilesReceived(paths);
        }
        ReceiveSharingIntent.instance.reset();
      }).catchError((err) {
        print("Error getting initial media: $err");
      });
    } catch (e) {
      print("Error initializing receive service: $e");
    }
  }

  static void dispose() {
    _intentSubscription?.cancel();
  }
}