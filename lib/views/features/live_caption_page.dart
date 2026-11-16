// lib/views/features/live_caption_page.dart
// State Machine Refactoring Agent — Production Implementation
// Continuous loop automation · 10s idle display reset · 3-mode language schema · VN ASCII fallback

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as sstt;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:demo_ai_even/services/text_service.dart';

// ── Language Mode Schema ─────────────────────────────────────────────────────
/// Simplified language schema for frictionless user interaction.
enum LanguageMode {
  english,               // Brand Label: "English"
  vietnameseWithAccents, // Brand Label: "Có Dấu"
  vietnameseNoAccents    // Brand Label: "Không Dấu"
}

// ── Widget ───────────────────────────────────────────────────────────────────
class LiveCaptionPage extends StatefulWidget {
  const LiveCaptionPage({super.key});

  @override
  State<LiveCaptionPage> createState() => _LiveCaptionPageState();
}

// ── State ────────────────────────────────────────────────────────────────────
class _LiveCaptionPageState extends State<LiveCaptionPage>
    with WidgetsBindingObserver {

  // ── Speech Engine ──────────────────────────────────────────────────────────
  final stt.SpeechToText _stt = stt.SpeechToText();

  // ── Transcript Buffers ─────────────────────────────────────────────────────
  final List<String> _finalizedSentences = <String>[];
  String _currentPartial = '';

  // ── Active Configuration Registry ─────────────────────────────────────────
  LanguageMode _activeLanguageMode = LanguageMode.vietnameseWithAccents;

  // ── Operational Status Hooks ───────────────────────────────────────────────
  bool _isListening = false;
  bool _sendToGlasses = true;

  // ── Display Power Saving & Mic Source ─────────────────────────────────────
  bool _isDisplayActive = true;   // Tracks whether the glasses HUD screen is awake
  bool _useGlassesMic = false;    // Tracks selected mic source: phone (false) or glasses (true)

  // ── System Hardware Watchdog Timers ────────────────────────────────────────
  Timer? _throttleSendTimer;
  Timer? _keepAliveTimer;
  Timer? _inactivityDisplayResetTimer;

  // ── Time Bookkeeping ────────────────────────────────────────────────────
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHeard = DateTime.fromMillisecondsSinceEpoch(0); // Used by display sleep engine

  // ── Payload Cache (for re-arming out-of-sync states after resume) ──────────
  String _lastTransmittedPayloadCache = '';

  // ── Android foreground-service channel scaffold ────────────────────────────
  static const _captionServiceChannel = MethodChannel('caption_service');
  static const _audioRoute = MethodChannel('audio_route');

  // ── Config ─────────────────────────────────────────────────────────────────
  static const _throttleInterval = Duration(milliseconds: 800);
  static const _keepAliveTick   = Duration(milliseconds: 900);
  static const _inactivityClear = Duration(seconds: 12); // 12-second display sleep per newtask spec

  // ═══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSpeechSubsystem();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _throttleSendTimer?.cancel();
    _keepAliveTimer?.cancel();
    _inactivityDisplayResetTimer?.cancel();
    _executeStopListening();
    super.dispose();
  }

  /// Lifecycle Watchdog Hook: Fixes the "connected but not displaying on glasses" breakdown.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('Lifecycle state mutation observed: $state');
    if (state == AppLifecycleState.paused) {
      await TextService.get.stopTextSendingByOS();
    } else if (state == AppLifecycleState.resumed) {
      // Re-verify speech engine continuity and force flush cache to glasses display.
      _synchronizeGlassesDisplayCache();
      if (!_isListening) {
        await _executeStartListening();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Initialization
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initializeSpeechSubsystem() async {
    if (await _ensureFgMicPermissions()) {
      try {
        await _captionServiceChannel.invokeMethod('startService');
      } catch (e) {
        debugPrint('startService error: $e');
      }
    }

    try {
      final ok = await _stt.initialize(
        onError: (errorDetails) {
          debugPrint('Speech Pipeline Exception: $errorDetails');
          // Self-Healing: If engine encounters transient mic drops, kick-start the loop
          if (_isListening) _forceRestartListeningLoop();
        },
        onStatus: (statusUpdate) {
          debugPrint('Speech Engine Hardware State: $statusUpdate');
          // Critical Background Hook: If engine stops but user wants it active, restart automatically
          if (statusUpdate == 'notListening') {
            if (mounted) setState(() => _isListening = false);
            if (DateTime.now().difference(_lastStart) > const Duration(milliseconds: 400)) {
              _executeStartListening();
            }
          }
        },
      );

      if (!mounted) return;
      if (ok) {
        await _executeStartListening();
        _startKeepAliveLoop();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speech recognition not available on this device.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Critical breakdown initializing Speech Engine: $e');
    }
  }

  Future<bool> _ensureFgMicPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.bluetoothConnect,
      if (Platform.isAndroid) Permission.notification,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Keep-Alive Loop
  // ═══════════════════════════════════════════════════════════════════════════

  void _startKeepAliveLoop() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveTick, (_) async {
      if (!_isListening &&
          DateTime.now().difference(_lastStart) > const Duration(milliseconds: 500)) {
        await _executeStartListening();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Start / Stop / Force-Restart Listening
  // ═══════════════════════════════════════════════════════════════════════════

  /// Starts capturing audio input.
  /// Reads _useGlassesMic to dynamically route to the glasses' BT mic or the phone mic.
  Future<void> _executeStartListening() async {
    if (_isListening) return;
    if (_stt.isAvailable != true) {
      await _stt.initialize(
        onStatus: (s) {
          if (s == 'notListening' && mounted) setState(() => _isListening = false);
        },
        onError: (e) => debugPrint('STT error: $e'),
      );
    }

    _lastStart = DateTime.now();

    // Resolve localized hardware token from active language mode
    final String hardwareLocaleToken =
        (_activeLanguageMode == LanguageMode.english) ? 'en_US' : 'vi_VN';

    // ── Dynamic Microphonic Input Selection ─────────────────────────────────
    if (_useGlassesMic) {
      debugPrint('Configuring Speech Engine input → Even Realities Glasses Built-in Microphone (BT route)');
      try {
        // Route the OS audio input to the connected Bluetooth device (glasses mic)
        await _audioRoute.invokeMethod('useVoiceCommMode', {'enable': true});
        await _audioRoute.invokeMethod('routeToBluetooth');
      } catch (e) {
        debugPrint('Glasses mic routing error: $e — falling back to phone mic');
      }
    } else {
      debugPrint('Configuring Speech Engine input → Phone Built-in Microphone');
      try {
        await _audioRoute.invokeMethod('useVoiceCommMode', {'enable': false});
        await _audioRoute.invokeMethod('routeToPhoneMic');
      } catch (_) {}
    }

    final started = await _stt.listen(
      onResult: _processIncomingSpeechFrames,
      listenFor: const Duration(hours: 4),   // Overrides standard short system listening cuts
      pauseFor: const Duration(seconds: 20), // Keeps tracking across long operational silent blocks
      localeId: hardwareLocaleToken,
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );

    if (mounted && started == true) {
      setState(() => _isListening = true);
    }
    _refreshInactivityTimer();
  }

  /// Halts speech capture explicitly.
  Future<void> _executeStopListening() async {
    if (!_isListening) return;
    await _stt.stop();
    _inactivityDisplayResetTimer?.cancel();
    if (mounted) setState(() => _isListening = false);
  }

  /// Structural Self-Healing Loop Automation.
  void _forceRestartListeningLoop() {
    _stt.stop().then((_) {
      if (mounted) _executeStartListening();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Frame Processing Pipeline
  // ═══════════════════════════════════════════════════════════════════════════

  void _processIncomingSpeechFrames(sstt.SpeechRecognitionResult result) {
    _lastHeard = DateTime.now(); // Timestamp of last heard speech — feeds display sleep engine

    // 1. Reset 12-second countdown on every incoming speech frame
    _refreshInactivityTimer();

    String words = result.recognizedWords;
    if (words.isEmpty) return;

    // Vietnamese ASCII fallback — strip diacritics when "Không Dấu" mode is active
    if (_activeLanguageMode == LanguageMode.vietnameseNoAccents) {
      words = _stripVietnameseDiacritics(words);
    }

    if (result.finalResult) {
      if (words.trim().isNotEmpty) {
        _finalizedSentences.add(words.trim());
        // Keep history bounded — cap at 200 sentences
        if (_finalizedSentences.length > 200) {
          _finalizedSentences.removeRange(0, _finalizedSentences.length - 200);
        }
      }
      _currentPartial = '';
    } else {
      _currentPartial = words;
    }

    // 2. Clear-to-Wake Strategy: immediately wake display when speech hits the pipeline
    if (!_isDisplayActive) {
      debugPrint('Speech detected! Automatically waking up smart glasses HUD matrix.');
      if (mounted) setState(() => _isDisplayActive = true);
    }

    _dispatchDataStreamToGlasses();
    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Glasses Payload Pipeline
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generates the rolling window display payload for the smart glasses.
  /// Constraint: Exactly last 2 finalized sentences + 1 working partial sentence segment.
  String _compileGlassesPayload() {
    final List<String> dynamicPayloadWindow = [];

    // Extract the final segments from the stable sentence log
    final take = _finalizedSentences.length >= 2 ? 2 : _finalizedSentences.length;
    if (take > 0) {
      dynamicPayloadWindow.addAll(_finalizedSentences.sublist(_finalizedSentences.length - take));
    }

    // Append the active talking segment if present
    if (_currentPartial.trim().isNotEmpty) {
      dynamicPayloadWindow.add(_currentPartial.trim());
    }

    while (dynamicPayloadWindow.length > 3) { dynamicPayloadWindow.removeAt(0); }

    return dynamicPayloadWindow.join('\n');
  }

  /// Sends the current text to the glasses hardware layer (throttled).
  /// Instantly blocks transmissions if _isDisplayActive is false — prevents
  /// unnecessary BLE traffic during quiet display-sleep moments.
  void _dispatchDataStreamToGlasses() {
    if (!_sendToGlasses) return;
    if (!_isDisplayActive) return; // ← Display sleep gate: block BLE when screen is off
    if (_throttleSendTimer?.isActive == true) return;

    _throttleSendTimer = Timer(_throttleInterval, () async {
      final String generatedPayload = _compileGlassesPayload();

      // Bandwidth Optimization Rule: Skip transmission if payload matches the last sent data
      if (generatedPayload == _lastTransmittedPayloadCache) return;
      _lastTransmittedPayloadCache = generatedPayload;

      if (generatedPayload.isNotEmpty) {
        await TextService.get.startSendText(generatedPayload);
      }
    });
  }

  /// Explicitly synchronized cache flush for application recovery phases.
  void _synchronizeGlassesDisplayCache() {
    debugPrint('Flushing cached transmission history to BLE stream...');
    if (_lastTransmittedPayloadCache.isNotEmpty && _sendToGlasses) {
      TextService.get.startSendText(_lastTransmittedPayloadCache);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Inactivity Timer
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tracks inactivity — after 12 seconds of silence, sleeps the glasses HUD.
  void _refreshInactivityTimer() {
    _inactivityDisplayResetTimer?.cancel();
    _inactivityDisplayResetTimer = Timer(_inactivityClear, () {
      if (!mounted) return;
      _clearGlassesHardwareDisplayMatrix();
    });
  }

  /// Turns off the glasses HUD matrix to conserve hardware battery cells.
  void _clearGlassesHardwareDisplayMatrix() {
    if (!_isDisplayActive) return; // Already asleep — no-op
    // Double-check: only sleep if we've truly been silent for the full inactivity window
    final idleFor = DateTime.now().difference(_lastHeard);
    if (idleFor < _inactivityClear) return;
    debugPrint('12-second silence reached: Sending sleep frame to glasses HUD.');
    if (mounted) setState(() => _isDisplayActive = false);
    _lastTransmittedPayloadCache = '';
    if (_sendToGlasses) {
      // Push empty payload to shut off display pixels
      TextService.get.startSendText('');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Vietnamese ASCII Transmutation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Highly Optimized ASCII Transmutation Logic.
  /// Removes diacritics from Vietnamese text while preserving spaces and layout formatting.
  String _stripVietnameseDiacritics(String sourceText) {
    if (sourceText.isEmpty) return sourceText;

    const Map<String, String> groups = {
      'a': 'àáảãạăắằẳẵặâấầẩẫậ',
      'A': 'ÀÁẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬ',
      'e': 'èéẻẽẹêềếểễệ',
      'E': 'ÈÉẺẼẸÊỀẾỂỄỆ',
      'i': 'ìíỉĩị',
      'I': 'ÌÍỈĨỊ',
      'o': 'òóỏõọôồốổỗộơờớởỡợ',
      'O': 'ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ',
      'u': 'ùúủũụưừứửữự',
      'U': 'ÙÚỦŨỤƯỪỨỬỮỰ',
      'y': 'ỳýỷỹỵ',
      'Y': 'ỲÝỶỸỴ',
      'd': 'đ',
      'D': 'Đ',
    };

    String out = sourceText;
    groups.forEach((base, chars) {
      for (final ch in chars.runes) {
        out = out.replaceAll(String.fromCharCode(ch), base);
      }
    });
    return out;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Session Management
  // ═══════════════════════════════════════════════════════════════════════════

  /// Completely flushes local memory logs.
  void _wipeLocalTranscriptStructures() {
    setState(() {
      _finalizedSentences.clear();
      _currentPartial = '';
      _lastTransmittedPayloadCache = '';
    });
    if (_sendToGlasses) TextService.get.startSendText('');
  }

  // Audio route helpers
  Future<void> _routePhone() async {
    try {
      await _audioRoute.invokeMethod('useVoiceCommMode', {'enable': false});
      await _audioRoute.invokeMethod('routeToPhoneMic');
    } catch (_) {}
    if (_isListening) await _stt.stop();
    await _executeStartListening();
  }

  Future<void> _routeBluetooth() async {
    try {
      await _audioRoute.invokeMethod('useVoiceCommMode', {'enable': true});
      await _audioRoute.invokeMethod('routeToBluetooth');
    } catch (_) {}
    if (_isListening) await _stt.stop();
    await _executeStartListening();
  }

  Future<void> _routeWiredUsb() async {
    try {
      await _audioRoute.invokeMethod('useVoiceCommMode', {'enable': true});
      await _audioRoute.invokeMethod('routeToWiredOrUsb');
    } catch (_) {}
    if (_isListening) await _stt.stop();
    await _executeStartListening();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Full Flowing Transcript (for phone UI)
  // ═══════════════════════════════════════════════════════════════════════════

  String _fullTranscript() {
    final parts = <String>[];
    parts.addAll(_finalizedSentences);
    if (_currentPartial.isNotEmpty) parts.add(_currentPartial);
    String out = parts.join(' ');
    if (_activeLanguageMode == LanguageMode.vietnameseNoAccents) {
      out = _stripVietnameseDiacritics(out);
    }
    return out;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final screenText = _fullTranscript();

    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        title: const Text(
          'EvenRealities Live Engine',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF1A1A1E),
        elevation: 0,
        actions: [
          // Send-to-glasses toggle
          IconButton(
            tooltip: _sendToGlasses ? 'Send to Glasses: ON' : 'Send to Glasses: OFF',
            icon: Icon(
              _sendToGlasses ? Icons.cast_connected : Icons.cast,
              color: _sendToGlasses ? Colors.greenAccent : Colors.white38,
            ),
            onPressed: () => setState(() => _sendToGlasses = !_sendToGlasses),
          ),
          // Session reset
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.amberAccent),
            onPressed: _wipeLocalTranscriptStructures,
            tooltip: 'Reset Session Data',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Language Mode Selector ───────────────────────────────────────
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
                  'DISPLAY MODES (CẤU HÌNH HIỂN THỊ)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.white60,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ToggleButtons(
                      direction: Axis.horizontal,
                      borderRadius: BorderRadius.circular(8),
                      selectedBorderColor: Colors.blueAccent,
                      selectedColor: Colors.white,
                      fillColor: Colors.blueAccent.withValues(alpha: 0.2),
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
                        Text('English',    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text('Có Dấu',    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text('Không Dấu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Audio Route Quick Controls ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Chip(
                  avatar: Icon(_isListening ? Icons.mic : Icons.mic_off, size: 16),
                  label: Text(
                    _isListening ? 'Mic: ON' : 'Mic: OFF',
                    style: TextStyle(
                      color: _isListening ? Colors.greenAccent : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: const Color(0xFF1A1A1E),
                  side: BorderSide(
                    color: _isListening ? Colors.greenAccent.withValues(alpha: 0.4) : Colors.white10,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _routePhone,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Phone', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: _routeBluetooth,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('BT', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: _routeWiredUsb,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Wired/USB', style: TextStyle(fontSize: 11)),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () async {
                      try { await _captionServiceChannel.invokeMethod('startService'); } catch (e) {
                      debugPrint('BG startService error: $e');
                    }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('BG', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Flowing Transcript Container ─────────────────────────────────
          Expanded(
            child: GestureDetector(
              onLongPress: _wipeLocalTranscriptStructures,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1E),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      screenText.isEmpty
                          ? 'Listening channel inactive. Toggle the master microphone switch to capture audio...'
                          : screenText,
                      style: TextStyle(
                        color: screenText.isEmpty
                            ? Colors.white24
                            : const Color(0xFF39FF14),
                        fontSize: 16.0,
                        height: 1.6,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Glasses Mic Toggle ───────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 0),
              title: Text(
                _useGlassesMic ? 'Glasses Mic' : 'Phone Mic',
                style: TextStyle(
                  color: _useGlassesMic ? Colors.blueAccent : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _useGlassesMic
                    ? 'Streaming audio from Even Realities glasses mic via BT'
                    : 'Using phone built-in microphone (default)',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              secondary: Icon(
                _useGlassesMic ? Icons.bluetooth_audio : Icons.phone_android,
                color: _useGlassesMic ? Colors.blueAccent : Colors.white38,
                size: 20,
              ),
              value: _useGlassesMic,
              activeThumbColor: Colors.blueAccent,
              onChanged: (bool value) {
                setState(() => _useGlassesMic = value);
                // Hot-swap audio input hardware context dynamically
                if (_isListening) _forceRestartListeningLoop();
              },
            ),
          ),

          // ── Display Sleep Status Indicator ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: Row(
              children: [
                Icon(
                  _isDisplayActive ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: _isDisplayActive ? Colors.greenAccent : Colors.white24,
                ),
                const SizedBox(width: 6),
                Text(
                  _isDisplayActive
                      ? 'Glasses HUD: ACTIVE'
                      : 'Glasses HUD: SLEEPING (speak to wake)',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDisplayActive ? Colors.greenAccent : Colors.white24,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // ── Core System Mic Control Panel ────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 10.0, bottom: 28.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  onPressed: _isListening ? _executeStopListening : _executeStartListening,
                  label: Text(
                    _isListening ? 'MIC ON (ACTIVE)' : 'MIC OFF (MUTED)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      fontSize: 12,
                    ),
                  ),
                  icon: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                    size: 18,
                  ),
                  backgroundColor: _isListening ? Colors.redAccent : Colors.blueAccent,
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
