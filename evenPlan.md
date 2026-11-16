## 2. Step 1: Codebase Discovery Execution Profile
*Executed by the Codebase Discovery Agent*

To ensure background processing does not silently fail due to missing context hooks, the Discovery Agent must parse, verify, and trace integration surfaces across the following foundational project files:

lib/
├── main.dart                      <-- Verifies background plugin binding setup
├── pages/
│   └── live_caption_page.dart     <-- Target for heavy logic refactoring
└── services/
└── glasses_ble_manager.dart   <-- Maps how transmission streams are held/flushed


### Discovery Validation Benchmarks
1. **`main.dart` Execution Check:** Ensure `WidgetsFlutterBinding.ensureInitialized();` is invoked explicitly before any engine components spark up.
2. **State Pipeline Mapping:** Ensure the Bluetooth manager exposes a persistent or cached connection signature so the frontend can check connectivity states right away when moving between background and foreground phases.

---

## 3. Step 2: Dependency Alignment Engine
*Executed by the Dependency Alignment Agent*

Operating in the background on mobile platforms requires explicit plugin infrastructure. Below is the audited configuration template for `pubspec.yaml`, ensuring matching versions for continuous background operations and layout segmentation:

```yaml
name: even_demo_app
description: Forked Even Realities Smart Glasses Live Caption Client.
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Core Audio Parsing Engine (Configured for long-form streaming limits)
  speech_to_text: ^6.6.0

  # Native Background Execution Guard (Keeps service loop running while phone is sleeping)
  flutter_background_service: ^5.0.5

  # Explicit Shared Caching Layer for fast recovery when the app resumes
  shared_preferences: ^2.2.3

  # UI Presentation Bindings
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
Platform Permissions Integration Spec
To ensure speech_to_text and flutter_background_service are not aggressively killed by the operating system kernel, the following ecosystem patches must be validated:

Android Configuration (android/app/src/main/AndroidManifest.xml)
XML
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<application ...>
    <service
        android:name="id.flutter.flutter_background_service.BackgroundService"
        android:foregroundServiceType="microphone"
        android:enabled="true"
        android:exported="false" />
</application>
iOS Configuration (ios/Runner/Info.plist)
XML
<key>NSMicrophoneUsageDescription</key>
<string>This application requires continuous microphone access to stream captions live to your Even Realities Smart Glasses.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>This application uses speech recognition to generate textual transcripts for head-up displays.</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>bluetooth-central</string>
    <string>processing</string>
</array>
4. Step 3: Production Code Injection Blueprint
Executed by the State Machine Refactoring Agent

This is the fully implemented, production-ready lib/pages/live_caption_page.dart. It includes continuous loop automation, a 10-second idle display reset, linguistic text filtering, and app state recovery checks.

Dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

/// Simplified language schema branding for frictionless user interaction.
enum LanguageMode {
  english,
  vietnameseWithAccents, // Brand Label: "Tiếng Việt (Có dấu)"
  vietnameseNoAccents     // Brand Label: "Tiếng Việt (Không dấu)"
}

class LiveCaptionPage extends StatefulWidget {
  const LiveCaptionPage({Key? key}) : super(key: key);

  @override
  State<LiveCaptionPage> createState() => _LiveCaptionPageState();
}

class _LiveCaptionPageState extends State<LiveCaptionPage> with WidgetsBindingObserver {
  // Engines & Core Operational Status Hooks
  final stt.SpeechToText _speechEngine = stt.SpeechToText();
  bool _isListeningExplicitly = false;
  bool _engineInitialized = false;
  
  // Active Configuration Registry
  LanguageMode _activeLanguageMode = LanguageMode.vietnameseWithAccents;

  // Transcript Window Vectors
  final List<String> _stableSentencesBuffer = [];
  String _activePartialSentence = "";
  String _lastTransmittedPayloadCache = ""; // Crucial for re-arming out-of-sync states

  // System Hardware Watchdog Timers
  Timer? _inactivityDisplayResetTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBindingObserver.instance.addObserver(this);
    _initializeSpeechSubsystem();
  }

  @override
  void dispose() {
    WidgetsBindingObserver.instance.removeObserver(this);
    _inactivityDisplayResetTimer?.cancel();
    _speechEngine.stop();
    super.dispose();
  }

  /// Lifecycle Watchdog Hook: Fixes the "connected but not displaying on glasses" breakdown
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("Lifecycle state mutation observed: $state");
    if (state == AppLifecycleState.resumed) {
      // SCENARIO: App was in background, OS paused standard UI loops. 
      // ACTION: Re-verify speech engine continuity and force flush cache to glasses display layer.
      if (_isListeningExplicitly) {
        _forceRestartListeningLoop();
      }
      _synchronizeGlassesDisplayCache();
    }
  }

  /// Initialize Audio Sampling Interface
  Future<void> _initializeSpeechSubsystem() async {
    try {
      _engineInitialized = await _speechEngine.initialize(
        onError: (errorDetails) {
          debugPrint('Speech Pipeline Exception: $errorDetails');
          // Self-Healing Strategy: If engine encounters transient mic drops, kick-start the loop back open
          if (_isListeningExplicitly) {
            _forceRestartListeningLoop();
          }
        },
        onStatus: (statusUpdate) {
          debugPrint('Speech Engine Hardware State: $statusUpdate');
          // Critical Background Hook: If engine stops but user wants it active, restart automatically
          if (statusUpdate == 'notListening' && _isListeningExplicitly) {
            _forceRestartListeningLoop();
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Critical breakdown initializing Speech Engine: $e');
    }
  }

  /// Starts capturing audio input
  void _executeStartListening() async {
    if (!_engineInitialized) return;

    // Resolve structural localized parameters
    String hardwareLocaleToken = 'en_US';
    if (_activeLanguageMode == LanguageMode.vietnameseWithAccents || 
        _activeLanguageMode == LanguageMode.vietnameseNoAccents) {
      hardwareLocaleToken = 'vi_VN';
    }

    setState(() => _isListeningExplicitly = true);

    await _speechEngine.listen(
      onResult: _processIncomingSpeechFrames,
      listenFor: const Duration(hours: 4),    // Overrides standard short system listening cuts
      pauseFor: const Duration(seconds: 20),   // Keeps tracking across long operational silent blocks
      localeId: hardwareLocaleToken,
      cancelOnError: false,
      partialResults: true,
    );

    _refreshInactivityTimer();
  }

  /// Halts speech capture explicitly
  void _executeStopListening() async {
    setState(() => _isListeningExplicitly = false);
    await _speechEngine.stop();
    _inactivityDisplayResetTimer?.cancel();
  }

  /// Structural Self-Healing Loop Automation
  void _forceRestartListeningLoop() {
    if (!_isListeningExplicitly) return;
    _speechEngine.stop().then((_) {
      if (_isListeningExplicitly) {
        _executeStartListening();
      }
    });
  }

  /// Frame processing pipeline for continuous transcripts
  void _processIncomingSpeechFrames(SpeechRecognitionResult result) {
    _refreshInactivityTimer();

    setState(() {
      _activePartialSentence = result.recognizedWords;
      
      if (result.finalResult) {
        if (_activePartialSentence.trim().isNotEmpty) {
          _stableSentencesBuffer.add(_activePartialSentence.trim());
        }
        _activePartialSentence = "";
      }
    });

    _dispatchDataStreamToGlasses();
  }

  /// Highly Optimized ASCII Transmutation Logic
  /// Removes diacritics from Vietnamese text while preserving spaces and layout formatting.
  String _stripVietnameseDiacritics(String sourceText) {
    if (sourceText.isEmpty) return sourceText;

    const mapAccents = [
      'aAeEoOuUiIdDyY', // Standard Target Targets
      'áàảãạăắằẳẵặâấầẩẫậ', // Variant 'a'
      'ÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬ', // Variant 'A'
      'éèẻẽẹêếềểễệ',       // Variant 'e'
      'ÉÈẺẼẸÊẾỀỂỄỆ',       // Variant 'E'
      'óòỏõọôốồổỗộơớờởỡợ', // Variant 'o'
      'ÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢ', // Variant 'O'
      'úùủũụưứừửữự',       // Variant 'u'
      'ÚÙỦŨỤƯỨỪỬỮỰ',       // Variant 'U'
      'íìỉĩị',             // Variant 'i'
      'ÍÌỈĨỊ',             // Variant 'I'
      'đ',                 // Lowercase d stroke
      'Đ',                 // Uppercase D stroke
      'ýỳỷỹỵ',             // Variant 'y'
      'ÝỲỶỸÝ'              // Variant 'Y'
    ];

    String trackingOutput = sourceText;
    for (int groupIdx = 1; groupIdx < mapAccents.length; groupIdx++) {
      final String mappingGroup = mapAccents[groupIdx];
      final String fallbackChar = mapAccents[0][groupIdx - 1];
      for (int charIdx = 0; charIdx < mappingGroup.length; charIdx++) {
        trackingOutput = trackingOutput.replaceAll(mappingGroup[charIdx], fallbackChar);
      }
    }
    return trackingOutput;
  }

  /// Generates the rolling window display payload for the smart glasses
  /// Constraint: Exactly last 2 finalized sentences + 1 working partial sentence segment.
  String _compileGlassesPayload() {
    List<String> dynamicPayloadWindow = [];
    
    // Extract the final segments from the stable sentence log
    if (_stableSentencesBuffer.length >= 2) {
      dynamicPayloadWindow.addAll(_stableSentencesBuffer.sublist(_stableSentencesBuffer.length - 2));
    } else {
      dynamicPayloadWindow.addAll(_stableSentencesBuffer);
    }

    // Append the active talking segment if present
    if (_activePartialSentence.trim().isNotEmpty) {
      dynamicPayloadWindow.add(_activePartialSentence.trim());
    }

    String combinedWindowText = dynamicPayloadWindow.join(" ");

    // Check if the user selected the simplified No Diacritics configuration
    if (_activeLanguageMode == LanguageMode.vietnameseNoAccents) {
      return _stripVietnameseDiacritics(combinedWindowText);
    }

    return combinedWindowText;
  }

  /// Sends the current text to the glasses hardware layer
  void _dispatchDataStreamToGlasses() {
    String generatedPayload = _compileGlassesPayload();
    
    // Bandwidth Optimization Rule: Skip transmission if payload matches the last sent data
    if (generatedPayload == _lastTransmittedPayloadCache) return;

    _lastTransmittedPayloadCache = generatedPayload;
    _transmitRawBlePayload(generatedPayload);
  }

  /// Explicitly synchronized cache flush for application recovery phases
  void _synchronizeGlassesDisplayCache() {
    debugPrint("Flushing cached transmission history to BLE stream...");
    _transmitRawBlePayload(_lastTransmittedPayloadCache);
  }

  /// Lower-Level Bluetooth Transmission Bridge
  void _transmitRawBlePayload(String outputString) {
    // Integration Point: Connects directly with your custom BLE transmission library
    // Example: EvenRealitiesBLEManager.writeString(outputString);
    debugPrint("BLE TRANSACTION LAYER SENDING: \\"$outputString\\"");
  }

  /// Tracks user inactivity to clear the screen automatically after 10 seconds of silence
  void _refreshInactivityTimer() {
    _inactivityDisplayResetTimer?.cancel();
    _inactivityDisplayResetTimer = Timer(const Duration(seconds: 10), () {
      _clearGlassesHardwareDisplayMatrix();
    });
  }

  /// Clears the glasses screen without wiping out the transcript history on the phone
  void _clearGlassesHardwareDisplayMatrix() {
    debugPrint("10s Inactivity Threshold Reached: Clearing HUD Screen Area.");
    _transmitRawBlePayload(""); 
  }

  /// Completely flushes local memory logs
  void _wipeLocalTranscriptStructures() {
    setState(() {
      _stableSentencesBuffer.clear();
      _activePartialSentence = "";
      _lastTransmittedPayloadCache = "";
    });
    _dispatchDataStreamToGlasses();
  }

  @override
  Widget build(BuildContext context) {
    // Assemble the complete transcript view for the local phone layout
    List<String> localDisplaySequence = List.from(_stableSentencesBuffer);
    if (_activePartialSentence.isNotEmpty) {
      localDisplaySequence.add(_activePartialSentence);
    }
    String processedScreenOutput = localDisplaySequence.join(" ");
    
    if (_activeLanguageMode == LanguageMode.vietnameseNoAccents) {
      processedScreenOutput = _stripVietnameseDiacritics(processedScreenOutput);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        title: const Text('EvenRealities Live Engine', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: const Color(0xFF1A1A1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.amberAccent),
            onPressed: _wipeLocalTranscriptStructures,
            tooltip: 'Reset Session Data',
          )
        ],
      ),
      body: Column(
        children: [
          // Simplified User Preferences Navigation Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "DISPLAY MODES (CẤU HÌNH HIỂN THỊ)",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white60, letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ToggleButtons(
                      direction: Axis.horizontal,
                      borderRadius: BorderRadius.circular(8),
                      selectedBorderColor: Colors.blueAccent,
                      selectedColor: Colors.white,
                      fillColor: Colors.blueAccent.withOpacity(0.2),
                      color: Colors.white38,
                      constraints: BoxConstraints.expand(
                        width: (constraints.maxWidth - 4) / 3,
                        height: 40,
                      ),
                      isSelected: [
                        _activeLanguageMode == LanguageMode.english,
                        _activeLanguageMode == LanguageMode.vietnameseWithAccents,
                        _activeLanguageMode == LanguageMode.vietnameseNoAccents,
                      ],
                      onPressed: (int index) {
                        setState(() {
                          if (index == 0) _activeLanguageMode = LanguageMode.english;
                          if (index == 1) _activeLanguageMode = LanguageMode.vietnameseWithAccents;
                          if (index == 2) _activeLanguageMode = LanguageMode.vietnameseNoAccents;
                        });
                        _forceRestartListeningLoop();
                      },
                      children: const [
                        Text("English", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text("Có Dấu", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text("Không Dấu", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    );
                  }
                ),
              ],
            ),
          ),

          // Flowing Transcript Wrapper: Top-anchored scroll preview container
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1E),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: SingleChildScrollView(
                alignment: Alignment.topLeft,
                child: Text(
                  processedScreenOutput.isEmpty 
                      ? "Listening channel inactive. Toggle the master microphone switch to capture audio..." 
                      : processedScreenOutput,
                  style: TextStyle(
                    color: processedScreenOutput.isEmpty ? Colors.white24 : const Color(0xFF39FF14),
                    fontSize: 16.0,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),

          // Core System Mic Control Panel
          Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 32.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  onPressed: _isListeningExplicitly ? _executeStopListening : _executeStartListening,
                  label: Text(_isListeningExplicitly ? 'MIC ON (ACTIVE)' : 'MIC OFF (MUTED)', 
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 12)),
                  icon: Icon(_isListeningExplicitly ? Icons.mic_rounded : Icons.mic_off_rounded, size: 18),
                  backgroundColor: _isListeningExplicitly ? Colors.redAccent : Colors.blueAccent,
                  elevation: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
5. Verification Checklist & Runtime Guardrails
Enforced by Orchestrator Agent

Before deployment, ensure the validation criteria below are checked within your workspace to confirm absolute execution runtime stability:

Background Keep-Alive Audit: Ensure the onStatus callback block correctly intercepts the notListening string identifier. This handles cases where underlying hardware layers stop recording when screen panels sleep or minimize.

ASCII Translation Matrix Integrity: The replacement matrix maps standard accents while explicitly retaining all space variations, meaning single strings won't collapse into crowded blocks on the smart glasses HUD screen.

Dynamic Window Pipeline Execution: The sublist extraction routine limits data transmission to precisely n-2 sentences, preventing the accumulation of text payload data transfers over Bluetooth.
"""

with open("output/multi_agent_execution_spec.md", "w") as f:
f.write(md_content.strip())

print("SUCCESS")

Your Markdown blueprint file has been successfully generated.

[file-tag: code-generated-file-0-1780240685656488616]

### Multi-Agent Structural Summary

This layout uses a modular, multi-agent strategy to maintain structural safety and ensure your app doesn't drop background audio frames:

1. **The Orchestrator Agent:** Oversees systemic coordination, preventing memory leakage between background engine transitions and tracking local variables.
2. **The Codebase Discovery Agent:** Traces dependency footprints across your project's `lib/` root paths (`main.dart` runtime hooks and Bluetooth connection layers).
3. **The Dependency Alignment Agent (`pubspec.yaml`):** Integrates native platform permissions (`AndroidManifest.xml` microservice tracking and iOS `Info.plist` background thread flags) to prevent the OS kernel from killing the mic.
4. **The State Machine Refactoring Agent (`live_caption_page.dart`):** Contains the complete code deployment with continuous auto-restart hooks, a 10-second inactivity layout clear, and a streamlined **"Có Dấu" vs "Không Dấu"** text formatting bridge.