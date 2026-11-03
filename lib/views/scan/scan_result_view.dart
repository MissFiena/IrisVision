import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/ocr_service.dart';
import '../../services/lang.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// C7 · Keputusan Imbasan.
/// Teks dibaca AUTOMATIK satu blok demi satu blok. Pengguna boleh
/// Jeda / Sambung, Sebelum, Seterusnya, atau ketik mana-mana blok untuk
/// lompat terus ke situ.
class ScanResultView extends StatefulWidget {
  final OcrResult result;
  const ScanResultView({super.key, required this.result});

  @override
  State<ScanResultView> createState() => _ScanResultViewState();
}

class _ScanResultViewState extends State<ScanResultView> {
  final TtsService _tts = TtsService.instance;
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];

  int _index = 0;
  bool _playing = false;
  int _runId = 0; // setiap kali main semula, larian lama dibatalkan
  bool _disposed = false;

  List<OcrBlock> get _blocks => widget.result.blocks;

  @override
  void initState() {
    super.initState();
    _keys.addAll(List.generate(_blocks.length, (_) => GlobalKey()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
  }

  Future<void> _intro() async {
    final bm = _tts.uiLang == TextLang.bm;
    final n = _blocks.length;
    final run = ++_runId;
    _set(() => _playing = true);
    await _tts.speak(
      bm ? 'Teks dijumpai. $n perenggan.' : 'Text found. $n ${n == 1 ? 'paragraph' : 'paragraphs'}.',
      lang: _tts.uiLang,
    );
    if (run == _runId && !_disposed) _playFrom(0);
  }

  void _set(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  // ============================ PLAYBACK ============================
  Future<void> _playFrom(int start) async {
    final run = ++_runId;
    await _tts.stop();
    _set(() {
      _index = start.clamp(0, _blocks.length - 1);
      _playing = true;
    });

    for (var i = _index; i < _blocks.length; i++) {
      if (run != _runId || _disposed) return; // dibatalkan
      _set(() => _index = i);
      _scrollTo(i);
      final before = _tts.interruptions;
      await _tts.speak(_blocks[i].text);
      if (_tts.interruptions != before) {
        // pengguna ketik butang lain semasa membaca -> berhenti di sini
        _runId++;
        _set(() => _playing = false);
        return;
      }
    }

    if (run != _runId || _disposed) return;
    _set(() => _playing = false);
    final bm = _tts.uiLang == TextLang.bm;
    await _tts.speak(bm ? 'Tamat.' : 'End.', lang: _tts.uiLang);
  }

  Future<void> _pause() async {
    _runId++; // batalkan gelung
    await _tts.stop();
    _set(() => _playing = false);
    _tts.speak(t('Jeda.', 'Paused.'), lang: _tts.uiLang, remember: false);
  }

  void _togglePlay() {
    HapticFeedback.mediumImpact();
    _playing ? _pause() : _playFrom(_index);
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_index < _blocks.length - 1) _playFrom(_index + 1);
  }

  void _prev() {
    HapticFeedback.selectionClick();
    _playFrom(_index > 0 ? _index - 1 : 0);
  }

  void _scrollTo(int i) {
    final ctx = _keys[i].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.2);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _runId++;
    _tts.stop();
    _scroll.dispose();
    super.dispose();
  }

  // ============================== UI ==============================
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = widget.result;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TopBar(title: Headline(context.tr('Teks Dijumpai', 'Text Found'), size: 24)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.tr(
                  '${_blocks.length} perenggan · ${r.wordCount} perkataan · ${r.latencyMs} ms',
                  '${_blocks.length} paragraphs · ${r.wordCount} words · ${r.latencyMs} ms',
                ),
                style: TextStyle(fontSize: 15, color: p.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _blocks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _BlockCard(
                  key: _keys[i],
                  number: i + 1,
                  total: _blocks.length,
                  text: _blocks[i].text,
                  active: i == _index,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _playFrom(i);
                  },
                ),
              ),
            ),
            _Controls(
              playing: _playing,
              canPrev: _index > 0,
              canNext: _index < _blocks.length - 1,
              onPrev: _prev,
              onToggle: _togglePlay,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final int number;
  final int total;
  final String text;
  final bool active;
  final VoidCallback onTap;

  const _BlockCard({
    super.key,
    required this.number,
    required this.total,
    required this.text,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      selected: active,
      label: context.tr('Perenggan $number daripada $total. $text', 'Paragraph $number of $total. $text'),
      hint: context.tr('Ketik dua kali untuk baca dari sini', 'Double tap to read from here'),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: active ? p.tint : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: active ? p.primary : p.border, width: active ? 3 : 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? p.highlight : p.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontFamily: AppFonts.heading,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: active ? p.onHighlight : p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 20, height: 1.45, color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kawalan bawah: [Sebelum]  [Main/Jeda besar]  [Seterusnya]
class _Controls extends StatelessWidget {
  final bool playing, canPrev, canNext;
  final VoidCallback onPrev, onToggle, onNext;

  const _Controls({
    required this.playing,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;

    Widget side(IconData icon, String label, bool enabled, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            enabled: enabled,
            label: label,
            excludeSemantics: true,
            onTap: enabled ? onTap : null,
            child: Material(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: enabled ? onTap : null,
                child: SizedBox(
                  height: 76,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 32, color: enabled ? p.textPrimary : p.border),
                      Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: enabled ? p.textSecondary : p.border)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          side(Icons.skip_previous_rounded, context.tr('Sebelum', 'Previous'), canPrev, onPrev),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Semantics(
              button: true,
              label: playing ? context.tr('Jeda', 'Pause') : context.tr('Main', 'Play'),
              excludeSemantics: true,
              onTap: onToggle,
              child: Material(
                color: p.primary,
                borderRadius: BorderRadius.circular(22),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  // Main/Jeda bertindak SERTA-MERTA (ketik sekali): jeda mesti segera
                  onTap: onToggle,
                  child: SizedBox(
                    height: 76,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: p.highlight, borderRadius: BorderRadius.circular(14)),
                          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 32, color: p.onHighlight),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          playing ? context.tr('Jeda', 'Pause') : context.tr('Main', 'Play'),
                          style: TextStyle(
                              fontFamily: AppFonts.heading, fontSize: 21, fontWeight: FontWeight.w700, color: p.onPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          side(Icons.skip_next_rounded, context.tr('Seterusnya', 'Next'), canNext, onNext),
        ],
      ),
    );
  }
}
