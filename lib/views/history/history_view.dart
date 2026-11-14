import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/database_service.dart';
import '../../services/lang.dart';
import '../../services/ocr_service.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../scan/scan_result_view.dart';

/// C8 · Sejarah imbasan (CRUD penuh, jadual `scan_history`).
///   Create : setiap imbasan teks disimpan automatik (skrin Imbas Teks)
///   Read   : senarai di sini; ketik satu rekod untuk dengar semula
///   Update : butang Namakan semula
///   Delete : butang Padam (satu) dan Padam semua
/// Hanya rekod milik akaun yang sedang log masuk dipaparkan.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final DatabaseService _db = DatabaseService.instance;
  final TtsService _tts = TtsService.instance;

  List<ScanRecord> _items = const [];
  bool _loading = true;
  bool _failed = false;

  String? get _uid => AppSettings.instance.userId;

  @override
  void initState() {
    super.initState();
    _load(announce: true);
  }

  Future<void> _load({bool announce = false}) async {
    final uid = _uid;
    try {
      if (uid == null || !_db.isReady) throw StateError('db/user tiada');
      final items = await _db.listScans(uid);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      debugPrint('❌ Ralat baca sejarah: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
    if (announce && mounted) {
      final n = _items.length;
      await _tts.announceScreen(
        context,
        n == 0 ? 'Sejarah. Tiada imbasan disimpan.' : 'Sejarah. $n imbasan disimpan.',
        n == 0 ? 'History. No saved scans.' : 'History. $n saved ${n == 1 ? 'scan' : 'scans'}.',
      );
    }
  }

  void _say(String bm, String en) => _tts.say(t(bm, en), lang: _tts.uiLang, remember: false);

  // ============================== READ ==============================
  Future<void> _open(ScanRecord r) async {
    HapticFeedback.selectionClick();
    final blocks = r.paragraphs.map(OcrBlock.new).toList();
    if (blocks.isEmpty) return;
    await _tts.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScanResultView(result: OcrResult(blocks: blocks, latencyMs: 0), historyTitle: r.title),
    ));
    if (mounted) _tts.announceScreen(context, 'Sejarah.', 'History.');
  }

  // ============================= UPDATE =============================
  Future<void> _rename(ScanRecord r) async {
    final uid = _uid;
    if (uid == null) return;
    _say('Namakan semula. Taip nama baru.', 'Rename. Type a new name.');
    final controller = TextEditingController(text: r.title);
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            void submit() {
              final v = controller.text.trim();
              if (v.isEmpty) {
                setLocal(() => error = context.tr('Nama tidak boleh kosong.', 'Name cannot be empty.'));
                return;
              }
              Navigator.of(context).pop(v);
            }

            return AlertDialog(
              title: Text(context.tr('Namakan semula', 'Rename')),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                style: const TextStyle(fontSize: 19),
                decoration: InputDecoration(
                  labelText: context.tr('Nama imbasan', 'Scan name'),
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Batal', 'Cancel'))),
                TextButton(onPressed: submit, child: Text(context.tr('Simpan', 'Save'))),
              ],
            );
          },
        );
      },
    );
    // tunggu animasi dialog tutup dulu, baru buang controller
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
    if (name == null || name == r.title || !mounted) return;
    final ok = await _db.renameScan(userId: uid, id: r.id, title: name);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    final msg = ok ? t('Nama disimpan: $name.', 'Name saved: $name.') : t('Gagal menyimpan nama.', 'Could not save the name.');
    showInfo(context, msg);
    _tts.say(msg, lang: _tts.uiLang, remember: false);
  }

  // ============================= DELETE =============================
  Future<bool> _confirm(String titleBm, String titleEn, String bodyBm, String bodyEn) async {
    HapticFeedback.mediumImpact();
    _say('$titleBm $bodyBm', '$titleEn $bodyEn');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr(titleBm, titleEn)),
        content: Text(context.tr(bodyBm, bodyEn)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('Batal', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Padam', 'Delete'), style: TextStyle(color: context.pal.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete(ScanRecord r) async {
    final uid = _uid;
    if (uid == null) return;
    final ok = await _confirm('Padam imbasan ini?', 'Delete this scan?', '"${r.title}" akan dipadam.',
        '"${r.title}" will be deleted.');
    if (!ok || !mounted) return;
    final done = await _db.deleteScan(userId: uid, id: r.id);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    final msg = done ? t('Imbasan dipadam.', 'Scan deleted.') : t('Gagal memadam.', 'Could not delete.');
    showInfo(context, msg);
    _tts.say(msg, lang: _tts.uiLang, remember: false);
  }

  Future<void> _deleteAll() async {
    final uid = _uid;
    if (uid == null || _items.isEmpty) return;
    final n = _items.length;
    final ok = await _confirm('Padam semua sejarah?', 'Delete all history?', '$n imbasan akan dipadam.',
        '$n ${n == 1 ? 'scan' : 'scans'} will be deleted.');
    if (!ok || !mounted) return;
    await _db.deleteAllScans(uid);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    final msg = t('Semua sejarah dipadam.', 'All history deleted.');
    showInfo(context, msg);
    _tts.say(msg, lang: _tts.uiLang, remember: false);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // =============================== UI ===============================
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final saving = AppSettings.instance.saveHistory.value;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: StatusBanner(
          message: context.tr('Sejarah tidak dapat dibuka. Sila tutup dan buka semula app.',
              'History could not be opened. Please close and reopen the app.'),
        ),
      );
    } else if (_items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 72, color: p.textSecondary),
              const SizedBox(height: 16),
              Text(
                context.tr('Tiada imbasan lagi.\nTeks yang anda imbas akan disimpan di sini.',
                    'No scans yet.\nText you scan will be saved here.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, height: 1.4, color: p.textSecondary),
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _HistoryCard(
          record: _items[i],
          number: i + 1,
          total: _items.length,
          onOpen: () => _open(_items[i]),
          onRename: () => _rename(_items[i]),
          onDelete: () => _delete(_items[i]),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TopBar(title: Headline(context.tr('Sejarah', 'History'), size: 26)),
            ),
            if (!saving)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.tr('Simpan sejarah dimatikan di Profil. Imbasan baru tidak disimpan.',
                      'Save history is off in Profile. New scans are not saved.'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.error),
                ),
              ),
            Expanded(child: body),
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    foregroundColor: p.error,
                    side: BorderSide(color: p.error, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    textStyle: const TextStyle(fontFamily: AppFonts.heading, fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 26),
                  label: Text(context.tr('Padam semua', 'Delete all')),
                  onPressed: _deleteAll,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Satu kad rekod: [ketik = dengar semula]  [Namakan semula] [Padam]
class _HistoryCard extends StatelessWidget {
  final ScanRecord record;
  final int number, total;
  final VoidCallback onOpen, onRename, onDelete;

  const _HistoryCard({
    required this.record,
    required this.number,
    required this.total,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final when = formatScanDate(record.createdAt, bm: context.isBm);
    final words = record.wordCount;
    final meta = context.tr('$when · $words perkataan', '$when · $words words');

    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: context.tr('Imbasan $number daripada $total. ${record.title}. $meta',
                    'Scan $number of $total. ${record.title}. $meta'),
                hint: context.tr('Ketik dua kali untuk dengar', 'Double tap to listen'),
                excludeSemantics: true,
                onTap: onOpen,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onOpen,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 76),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            record.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(meta, style: TextStyle(fontSize: 15, color: p.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SquareIconButton(
              icon: Icons.edit_outlined,
              tooltip: context.tr('Namakan semula ${record.title}', 'Rename ${record.title}'),
              onPressed: onRename,
            ),
            const SizedBox(width: 8),
            SquareIconButton(
              icon: Icons.delete_outline,
              tooltip: context.tr('Padam ${record.title}', 'Delete ${record.title}'),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// "14 Nov 2026, 9:05 PTG" / "14 Nov 2026, 9:05 PM" (tanpa pakej intl).
String formatScanDate(DateTime d, {required bool bm}) {
  const bmMonths = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ogo', 'Sep', 'Okt', 'Nov', 'Dis'];
  const enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final now = DateTime.now();
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? (bm ? 'PG' : 'AM') : (bm ? 'PTG' : 'PM');
  final time = '$h12:$mm $ampm';
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) return bm ? 'Hari ini, $time' : 'Today, $time';
  final month = (bm ? bmMonths : enMonths)[d.month - 1];
  return '${d.day} $month ${d.year}, $time';
}
