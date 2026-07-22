import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Strict Landscape Orientation Lock
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const BlixoApp());
  });
}

class BlixoApp extends StatelessWidget {
  const BlixoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BlixoHomeScreen(),
    );
  }
}

enum BlixoState { idle, listeningMode, happyResponse }

class BlixoHomeScreen extends StatefulWidget {
  const BlixoHomeScreen({super.key});

  @override
  State<BlixoHomeScreen> createState() => _BlixoHomeScreenState();
}

class _BlixoHomeScreenState extends State<BlixoHomeScreen>
    with SingleTickerProviderStateMixin {
  // Animation & Audio
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  late AudioPlayer _audioPlayer;

  // Speech Recognition
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isVoiceCommandActive = false; // "Blixo" wake-word flag

  // State & Expressions
  BlixoState _currentState = BlixoState.idle;
  String? _cloudHappyWebpUrl;

  // Local Random Audio Options
  final List<String> _localResponses = [
    'assets/hmm.mp3',
    'assets/what.mp3',
    'assets/yes.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _speech = stt.SpeechToText();

    // Floating Up-Down Motion
    _floatController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    // App Start par Mic permission aur Voice Listening start karo
    _initPermissionsAndVoice();
  }

  Future<void> _initPermissionsAndVoice() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      _startContinuousListening();
    }
  }

  void _startContinuousListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          // Continuous listening restart
          _listen();
        }
      },
      onError: (errorNotification) {
        _listen();
      },
    );

    if (available) {
      _listen();
    }
  }

  void _listen() {
    if (!_isListening) {
      _speech.listen(
        onResult: (result) {
          String words = result.recognizedWords.toLowerCase().trim();
          _handleVoiceCommand(words);
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      );
      setState(() => _isListening = true);
    }
  }

  void _handleVoiceCommand(String command) async {
    // 1. Check for Wake Word
    if (!_isVoiceCommandActive) {
      if (command.contains("blixo") || command.contains("hey blixo")) {
        _isVoiceCommandActive = true;
        _speech.stop();
        _isListening = false;

        // Visual state change to WHAT
        setState(() {
          _currentState = BlixoState.listeningMode;
        });

        // Local random response play karo (hmm / what / yes)
        String randomLocalAudio =
            _localResponses[Random().nextInt(_localResponses.length)];
        await _playAudio(randomLocalAudio, isAsset: true);

        // Listening dobara start user question ke liye
        _listen();
      }
    }
    // 2. Active Command Mode: Handling "Who am I"
    else {
      if (command.contains("who am i") || command.contains("hu am i")) {
        _speech.stop();
        _isListening = false;

        // Fetch & Play Dynamic Firebase Response
        await _triggerFirebaseResponse();

        // Reset Back to Idle Lock State
        _isVoiceCommandActive = false;
        setState(() {
          _currentState = BlixoState.idle;
        });

        // Resume Voice Engine
        _listen();
      }
    }
  }

  Future<void> _triggerFirebaseResponse() async {
    try {
      DatabaseReference dbRef = FirebaseDatabase.instance.ref();

      // Fetch Happy WebP URL
      DataSnapshot happyImgSnap = await dbRef.child('assets/eyes/happy').get();
      if (happyImgSnap.exists) {
        _cloudHappyWebpUrl = happyImgSnap.value.toString();
      }

      // Fetch Random Audio from 'responses/who_am_i'
      DataSnapshot audioSnap = await dbRef.child('responses/who_am_i').get();
      if (audioSnap.exists) {
        List<dynamic> audioList = audioSnap.value as List<dynamic>;
        String selectedAudioUrl =
            audioList[Random().nextInt(audioList.length)].toString();

        // Switch Eye to Happy Expression
        setState(() {
          _currentState = BlixoState.happyResponse;
        });

        // Play Cloud Audio & Wait till completion
        await _playAudio(selectedAudioUrl, isAsset: false);
      }
    } catch (e) {
      debugPrint("Firebase Dynamic Fetch Error: $e");
    }
  }

  Future<void> _playAudio(String path, {required bool isAsset}) async {
    try {
      if (isAsset) {
        await _audioPlayer.setAsset(path);
      } else {
        await _audioPlayer.setUrl(path);
      }
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _audioPlayer.dispose();
    _speech.stop();
    super.dispose();
  }

  // Expression Image Provider
  Widget _getExpressionImage() {
    switch (_currentState) {
      case BlixoState.listeningMode:
        return Image.asset(
          'assets/what.webp',
          key: const ValueKey('what_eye'),
          fit: BoxFit.cover,
        );

      case BlixoState.happyResponse:
        if (_cloudHappyWebpUrl != null && _cloudHappyWebpUrl!.isNotEmpty) {
          return Image.network(
            _cloudHappyWebpUrl!,
            key: const ValueKey('happy_eye'),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Image.asset('assets/idle.webp', fit: BoxFit.cover),
          );
        }
        return Image.asset('assets/idle.webp',
            key: const ValueKey('idle_fallback'), fit: BoxFit.cover);

      case BlixoState.idle:
      default:
        return Image.asset(
          'assets/idle.webp',
          key: const ValueKey('idle_eye'),
          fit: BoxFit.cover,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _floatAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _floatAnimation.value), // Floating effect
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500), // 0.5s Fade Out
                reverseDuration:
                    const Duration(milliseconds: 500), // 0.5s Fade In
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                child: _getExpressionImage(),
              ),
            );
          },
        ),
      ),
    );
  }
}
