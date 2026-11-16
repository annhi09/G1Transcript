// import 'dart:async';
// import 'dart:math';
// import 'package:demo_ai_even/services/evenai.dart';
// import 'package:demo_ai_even/services/proto.dart';
//
// class CaptionService {
//   static final CaptionService _instance = CaptionService._();
//   static CaptionService get instance => _instance;
//
//   CaptionService._();
//
//   static const int _chunkSize = 5;
//   static const int _intervalSeconds = 6;
//
//   List<String> _captions = [];
//   Timer? _timer;
//   int _currentChunkIndex = 0;
//   bool _isSending = false;
//
//   void updateCaption(String newText) {
//     _captions = _splitIntoChunks(newText.trim());
//     _currentChunkIndex = 0;
//     _restartTimer();
//   }
//
//   List<String> _splitIntoChunks(String text) {
//     final words = text.split(RegExp(r'\s+'));
//     final lines = <String>[];
//     String line = "";
//
//     for (var word in words) {
//       if ((line + word).length < 18) {
//         line += "$word ";
//       } else {
//         lines.add(line.trim());
//         line = "$word ";
//       }
//     }
//     if (line.isNotEmpty) lines.add(line.trim());
//     return lines;
//   }
//
//   void _restartTimer() {
//     _timer?.cancel();
//     _timer = Timer.periodic(const Duration(seconds: _intervalSeconds), (_) {
//       _sendNextChunk();
//     });
//   }
//
//   Future<void> _sendNextChunk() async {
//     if (_captions.isEmpty || _currentChunkIndex >= _captions.length) return;
//
//     final chunk = _captions
//         .skip(_currentChunkIndex)
//         .take(_chunkSize)
//         .map((e) => "$e\n")
//         .join();
//
//     _isSending = true;
//
//     final success = await Proto.sendEvenAIData(
//       chunk,
//       newScreen: EvenAIDataMethod.transferToNewScreen(0x01, 0x70),
//       pos: 0,
//       current_page_num: _getCurrentPage(),
//       max_page_num: _getTotalPages(),
//     );
//
//     if (success) {
//       _currentChunkIndex += _chunkSize;
//     } else {
//       // Retry next tick
//     }
//
//     _isSending = false;
//   }
//
//   int _getTotalPages() {
//     if (_captions.isEmpty) return 1;
//     return (_captions.length / _chunkSize).ceil();
//   }
//
//   int _getCurrentPage() {
//     return (_currentChunkIndex / _chunkSize).ceil() + 1;
//   }
//
//   void stop() {
//     _timer?.cancel();
//     _captions.clear();
//     _currentChunkIndex = 0;
//   }
// }

import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';
import 'package:demo_ai_even/services/text_service.dart';

class CaptionService with ChangeNotifier {
  static final CaptionService _instance = CaptionService._internal();
  factory CaptionService() => _instance;
  CaptionService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _transcription = '';
  String _languageCode = 'en_US';
  Timer? _sendTimer;
  String _lastSentText = '';

  bool get isListening => _isListening;
  String get transcription => _transcription;
  String get languageCode => _languageCode;

  Future<void> init() async {
    await _speech.initialize(
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == stt.SpeechToText.listeningStatus) {
          _isListening = true;
          notifyListeners();
        } else if (status == stt.SpeechToText.notListeningStatus) {
          _isListening = false;
          notifyListeners();
          if (TextService.isRunning) {
            _startListening();
          }
        }
      },
      onError: (error) {
        debugPrint('Speech error: ${error}');
        _isListening = false;
        notifyListeners();
        if (TextService.isRunning) {
          _startListening();
        }
      },
    );
  }



  void _startListening() {
    if (!_speech.isAvailable || _isListening) return;

    _speech.listen(
    // _speech.SpeechListenOptions(
      localeId: _languageCode,
      listenFor: const Duration(seconds: 10), // Listen for a period before restarting
      onResult: (result) {
        _transcription = result.recognizedWords;
        notifyListeners();
        _scheduleSendToGlasses(_transcription);
      },
      // SpeechListenOptions.cancelOnError: false,
     // SpeechListenOption.cancelOnError: false,
     cancelOnError: false,
      partialResults: true,
    );
  }

  void startCaptioning() {
    _transcription = '';
    TextService.get.stopTextSendingByOS();
    _startListening();
  }

  void stopCaptioning() {
    _isListening = false;
    _speech.stop();
    _sendTimer?.cancel();
    TextService.get.stopTextSendingByOS();
    notifyListeners();
  }

  void switchLanguage(String code) {
    if (_isListening) {
      _speech.stop();
    }
    _languageCode = code;
    _transcription = '';
    notifyListeners();
    if (TextService.isRunning) {
      _startListening();
    }
  }

  void _scheduleSendToGlasses(String text) {
    if (text.trim().isEmpty || text.trim() == _lastSentText) return;

    _sendTimer?.cancel();
    _sendTimer = Timer(const Duration(milliseconds: 500), () async {
      _lastSentText = text.trim();
      if (_lastSentText.isNotEmpty) {
        await TextService.get.startSendText(_lastSentText);
        debugPrint("Sent to glasses: $_lastSentText");
      }
    });
  }
}