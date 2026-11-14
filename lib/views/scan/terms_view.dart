import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/database_service.dart';
import '../../services/lang.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Istilah akademik yang dijumpai dalam teks imbasan, dengan terjemahan
/// BM <-> English (jadual academic_terms).
/// Ketik satu istilah: suara app sebut istilah itu, kemudian padanannya,
/// setiap satu dengan suara bahasa yang betul.
class TermsView extends StatefulWidget {
  final List<FoundTerm> terms;
  const TermsView({super.key, required this.terms});

  @override
  State<TermsView> createState() => _TermsViewState();
}

class _TermsViewState extends State<TermsView> {
  final TtsService _tts = TtsService.instance;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = widget.terms.length;
      _tts.announceScreen(
        context,
        'Istilah akademik. $n istilah dijumpai. Ketik satu untuk dengar terjemahan.',
        'Academic terms. $n ${n == 1 ? 'term' : 'terms'} found. Tap one to hear the translation.',
      );
    });
  }

  @override
  void dispose() {
    _run++;
    _tts.stop();
    super.dispose();
  }

  /// Contoh (app BM): "Hipotesis." [suara BM] -> "Dalam bahasa Inggeris:" [BM] -> "hypothesis" [EN]
  Future<void> _play(FoundTerm f) async {
    HapticFeedback.selectionClick();
    final run = ++_run;
    await _tts.stop();
    final writtenLang = f.foundInBm ? TextLang.bm : TextLang.en;
    final otherLang = f.foundInBm ? TextLang.en : TextLang.bm;
    final ui = _tts.uiLang;
    final bridge = f.foundInBm
        ? (ui == TextLang.bm ? 'Dalam bahasa Inggeris:' : 'In English:')
        : (ui == TextLang.bm ? 'Dalam Bahasa Melayu:' : 'In Malay:');

    await _tts.speak('${f.asWritten}.', lang: writtenLang, remember: false);
    if (run != _run || !mounted) return;
    await _tts.speak(bridge, lang: ui, remember: false);
    if (run != _run || !mounted) return;
    await _tts.speak(f.translation, lang: otherLang, remember: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bm = context.isBm;
    final terms = widget.terms;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: TopBar(title: Headline(context.tr('Istilah Akademik', 'Academic Terms'), size: 24)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                context.tr('${terms.length} istilah · ketik untuk dengar', '${terms.length} terms · tap to listen'),
                style: TextStyle(fontSize: 15, color: p.textSecondary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: terms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final f = terms[i];
                  final category = bm ? f.term.categoryBm : f.term.categoryEn;
                  final toLang = f.foundInBm
                      ? context.tr('bahasa Inggeris', 'English')
                      : context.tr('Bahasa Melayu', 'Malay');
                  return Semantics(
                    button: true,
                    // TalkBack sebut ringkas; sebutan sebenar oleh suara app bila diketik
                    label: '${f.asWritten}. ${context.tr('Dalam', 'In')} $toLang: ${f.translation}',
                    hint: context.tr('Ketik dua kali untuk dengar', 'Double tap to listen'),
                    excludeSemantics: true,
                    onTap: () => _play(f),
                    child: Material(
                      color: p.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: p.border, width: 1.5),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _play(f),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_cap(f.asWritten),
                                        style: TextStyle(
                                            fontFamily: AppFonts.heading,
                                            fontSize: 21,
                                            fontWeight: FontWeight.w700,
                                            color: p.textPrimary)),
                                    const SizedBox(height: 4),
                                    Text('→ ${f.translation}',
                                        style: TextStyle(fontSize: 19, color: p.accent, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(category, style: TextStyle(fontSize: 14, color: p.textSecondary)),
                                  ],
                                ),
                              ),
                              Icon(Icons.volume_up_rounded, size: 30, color: p.accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
