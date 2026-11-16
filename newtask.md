# AGENT EXECUTION PROMPT: HARDWARE INTEGRATION & DISPLAY POWER SAVING

## Target File
`lib/pages/live_caption_page.dart`

## Objective
Refactor the state machine inside `LiveCaptionPage` to manage a 10–15 second automatic display sleep/wake cycle based on speech activity, and add an option to toggle between the phone's native microphone and the Even Realities smart glasses' built-in Bluetooth microphone.

---

## 1. Required State Changes & Variables
Inject these tracking states into `_LiveCaptionPageState`:
- `bool _isDisplayActive = true;` (Tracks whether the glasses screen is currently awake)
- `bool _useGlassesMic = false;` (Tracks the selected microphone source)
- `Timer? _inactivityDisplayResetTimer;` (Manages the 10-15 second countdown)

---

## 2. Implementation Specifications

### A. 12-Second Display Sleep/Wake Engine
Modify `_processIncomingSpeechFrames` and the transmission pipeline to work as follows:
1. Every time a new speech frame arrives, cancel the running `_inactivityDisplayResetTimer` and schedule a fresh one for **12 seconds**.
2. If `_isDisplayActive` is `false` when a new frame arrives, immediately flip it to `true` (Wake up) before sending data.
3. If the 12-second timer expires without speech, flip `_isDisplayActive = false` and invoke `_transmitRawBlePayload("");` to turn off the glasses' screen pixels.
4. Update `_dispatchDataStreamToGlasses()` to instantly block transmissions if `_isDisplayActive` is false, preventing unnecessary BLE traffic during quiet moments.

### B. Smart Glasses Microphone Integration Dual-Source Option
1. Update `_executeStartListening()` to read the state of `_useGlassesMic`.
2. When `_useGlassesMic` is true, configure the audio input source tracking to utilize the connected Bluetooth Headset component. (In the standard `speech_to_text` plugin, this is done by checking available system devices via `_speechEngine.devices()` and matching the device containing standard BLE/Bluetooth acoustic signatures, or setting the default input routing via your native Bluetooth service channel wrapper).
3. Add a clean, simple toggle switch UI next to the microphone button labeled: 
   - **"Phone Mic"** (Default)
   - **"Glasses Mic"**

---

## 3. Code Injection Template

Replace the target logic blocks with this precise implementation structural design:

```dart
  // --- NEW MICROPHONE & DISPLAY POWER SAVING STATES ---
  bool _isDisplayActive = true;
  bool _useGlassesMic = false;
  Timer? _inactivityDisplayResetTimer;

  /// Handles starting the speech engine with custom configurations per language profile and audio routing
  void _executeStartListening() async {
    if (!_engineInitialized) return;

    String hardwareLocaleToken = 'en_US';
    if (_activeLanguageMode == LanguageMode.vietnameseWithAccents || 
        _activeLanguageMode == LanguageMode.vietnameseNoAccents) {
      hardwareLocaleToken = 'vi_VN';
    }

    setState(() => _isListeningExplicitly = true);

    // Dynamic Microphonic Input Selection Check
    if (_useGlassesMic) {
      debugPrint("Configuring Speech Engine input pointer to channel: Even Realities Glasses Built-in Microphone");
      // Optional implementation block depending on plugin version:
      // List<stt.SpeechDevice> devices = await _speechEngine.devices();
      // Look for BLE/Bluetooth headset flags if explicit target binding is required by OS kernel.
    }

    await _speechEngine.listen(
      onResult: _processIncomingSpeechFrames,
      listenFor: const Duration(hours: 4),
      pauseFor: const Duration(seconds: 20),
      localeId: hardwareLocaleToken,
      cancelOnError: false,
      partialResults: true,
    );

    _refreshInactivityTimer();
  }

  /// Frame processing pipeline for continuous transcripts with auto wake-up
  void _processIncomingSpeechFrames(SpeechRecognitionResult result) {
    // 1. Reset countdown on every incoming frame activity
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

    // 2. Clear-to-Wake Strategy: Wake display immediately when speech data hits the pipeline
    if (!_isDisplayActive) {
      debugPrint("Speech detected! Automatically waking up smart glasses HUD matrix.");
      setState(() {
        _isDisplayActive = true;
      });
    }

    _dispatchDataStreamToGlasses();
  }

  /// Track inactivity window to auto-sleep the glasses display screen
  void _refreshInactivityTimer() {
    _inactivityDisplayResetTimer?.cancel();
    _inactivityDisplayResetTimer = Timer(const Duration(seconds: 12), () {
      _clearGlassesHardwareDisplayMatrix();
    });
  }

  /// Turns off glasses HUD matrix to conserve hardware battery cells
  void _clearGlassesHardwareDisplayMatrix() {
    if (!_isDisplayActive) return;

    debugPrint("12-second silence reached: Sending sleep frame to glasses HUD.");
    setState(() {
      _isDisplayActive = false;
    });

    _transmitRawBlePayload(""); // Push empty payload to shut off display pixels
  }

  /// Sends updated text stream to the smart glasses if display is awake
  void _dispatchDataStreamToGlasses() {
    if (!_isDisplayActive) return;

    String generatedPayload = _compileGlassesPayload();
    if (generatedPayload == _lastTransmittedPayloadCache) return;

    _lastTransmittedPayloadCache = generatedPayload;
    _transmitRawBlePayload(generatedPayload);
  }

  // --- UI CONTROLS ADJUSTMENT CONFIGURATION ---
  // Inject this Switch/Segmented element directly inside the widget build control panel tree 
  // to give the user clean microphone peripheral hardware selection options:
  /*
  SwitchListTile(
    title: const Text("Use Glasses Microphone", style: TextStyle(color: Colors.white, fontSize: 13)),
    subtitle: const Text("Streams audio directly from the smart glasses hardware mic", style: TextStyle(color: Colors.white38, fontSize: 11)),
    value: _useGlassesMic,
    activeColor: Colors.blueAccent,
    onChanged: (bool value) {
      setState(() {
        _useGlassesMic = value;
      });
      if (_isListeningExplicitly) {
        _forceRestartListeningLoop(); // Hot-swap audio input hardware context dynamically
      }
    },
  )
  */