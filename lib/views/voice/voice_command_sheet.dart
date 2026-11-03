import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/lang.dart';
import '../../services/tts_service.dart';
import '../../services/voice_command_service.dart';
import '../../theme/app_theme.dart';

/// Panel "Mendengar..." yang muncul bila butang mic ditekan.
/// Pulangkan [VoiceResult] (atau null jika tiada suara / dibatalkan).
Future<VoiceResult?> showVoiceCommandSheet(BuildContext context) {
  return showModalBottomSheet<VoiceResult>(
    context: context,
    isDismissible: false, // tutup dengan butang Batal sahaja
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const _VoiceSheet(),
  );
}

enum _Phase { prompt, listening, noMic }

const _cancelled = VoiceResult(VoiceAction.cancelled, '', 0);

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> with SingleTickerProviderStateMixin {
  final _voice = VoiceCommandService.instance;
  final _tts = TtsService.instance;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  _Phase _phase = _Phase.prompt;
  String _heard = '';
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!await _voice.init()) {
      if (!mounted) return;
      setState(() => _phase = _Phase.noMic);
      _tts.announce(
        'Mikrofon tidak dapat digunakan. Sila benarkan kebenaran mikrofon dalam tetapan telefon.',
        'The microphone cannot be used. Please allow microphone permission in phone settings.',
      );
      return;
    }
    // Sebut "Ya?" DAHULU dan tunggu habis, supaya suara app tak didengar sebagai arahan
    await _tts.stop();
    await _tts.speak(t('Ya?', 'Yes?'), lang: _tts.uiLang, remember: false);
    if (!mounted || _closed) return;

    if (AppSettings.instance.vibrate.value) HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.listening);
    final result = await _voice.listen(
      onPartial: (w) {
        if (mounted) setState(() => _heard = w);
      },
    );
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _cancel() async {
    _closed = true;
    await _voice.cancel();
    _tts.announce('Dibatalkan.', 'Cancelled.', remember: false);
    if (mounted) Navigator.of(context).pop(_cancelled);
  }

  @override
  void dispose() {
    if (!_closed) _voice.cancel(); // ditutup dengan butang Kembali telefon
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final String title = switch (_phase) {
      _Phase.prompt => context.tr('Bersedia...', 'Getting ready...'),
      _Phase.listening => context.tr('Mendengar...', 'Listening...'),
      _Phase.noMic => context.tr('Mikrofon tidak dibenarkan', 'Microphone not allowed'),
    };
    final String hint = _phase == _Phase.noMic
        ? context.tr('Benarkan mikrofon dalam tetapan telefon.', 'Allow the microphone in phone settings.')
        : context.tr('Contoh: "kesan objek", "imbas teks", "bantuan"', 'Example: "detect object", "scan text", "help"');

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 20),
            // mic berdenyut semasa mendengar
            ExcludeSemantics(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final grow = _phase == _Phase.listening ? 14 * _pulse.value : 0.0;
                    return Container(
                      width: 112 + grow,
                      height: 112 + grow,
                      decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: _phase == _Phase.noMic ? p.error : p.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _phase == _Phase.noMic ? Icons.mic_off : Icons.mic,
                      size: 44,
                      color: p.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // TIDAK guna liveRegion: TalkBack yang membaca tajuk semasa mic
            // terbuka akan didengar sebagai arahan.
            Semantics(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AppFonts.heading, fontSize: 26, fontWeight: FontWeight.w800, color: p.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            // apa yang didengar (untuk pengguna yang nampak)
            ExcludeSemantics(
              child: Text(
                _heard.isEmpty ? hint : '"$_heard"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _heard.isEmpty ? 16 : 21,
                  height: 1.35,
                  fontWeight: _heard.isEmpty ? FontWeight.w400 : FontWeight.w700,
                  color: _heard.isEmpty ? p.textSecondary : p.accent,
                ),
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                side: BorderSide(color: p.border, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(fontFamily: AppFonts.heading, fontSize: 19, fontWeight: FontWeight.w700),
              ),
              onPressed: _phase == _Phase.noMic ? () => Navigator.of(context).pop(_cancelled) : _cancel,
              child: Text(_phase == _Phase.noMic ? context.tr('Tutup', 'Close') : context.tr('Batal', 'Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}
