import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Tajuk automatik untuk imbasan baru: ~40 aksara pertama teks,
/// dipotong di hujung perkataan. Pengguna boleh namakan semula kemudian.
String historyTitleFor(String text) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= 40) return clean;
  final cut = clean.substring(0, 40);
  final space = cut.lastIndexOf(' ');
  return '${space > 20 ? cut.substring(0, space) : cut}…';
}

/// Satu istilah akademik dengan padanan BM dan EN.
class AcademicTerm {
  final int id;
  final String bm, en, categoryBm, categoryEn;
  const AcademicTerm({
    required this.id,
    required this.bm,
    required this.en,
    required this.categoryBm,
    required this.categoryEn,
  });
}

/// Istilah yang dijumpai dalam teks, dan bahasa ia ditulis.
class FoundTerm {
  final AcademicTerm term;
  final bool foundInBm;
  const FoundTerm(this.term, {required this.foundInBm});

  String get asWritten => foundInBm ? term.bm : term.en;
  String get translation => foundInBm ? term.en : term.bm;
}

/// Satu rekod Sejarah imbasan.
class ScanRecord {
  final int id;
  final String userId;
  final String title;
  final String content; // perenggan dipisahkan dengan baris kosong
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScanRecord({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ScanRecord.fromRow(Map<String, Object?> r) => ScanRecord(
        id: r['id'] as int,
        userId: r['user_id'] as String,
        title: r['title'] as String,
        content: r['content'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      );

  List<String> get paragraphs =>
      content.split('\n\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  int get wordCount => content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

/// Pangkalan data SQLite dalam telefon (fail `irisvision.db`).
///
/// 5 jadual, 3NF (lihat docs/database.md):
///   users            1 baris setiap akaun Firebase (kunci = Firebase UID)
///   user_settings    tetapan app, 1:1 dengan users
///   scan_history     teks yang diimbas, 1:N dengan users
///   object_categories kategori objek (BM/EN)
///   object_labels    nama BM/EN setiap label model, N:1 dengan object_categories
///
/// Setiap query Sejarah ditapis dengan `user_id` -> pengguna hanya nampak
/// dan boleh ubah rekod sendiri (authorization).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const String _fileName = 'irisvision.db';
  static const int _version = 3; // v2: user_settings.tutorial_seen, v3: istilah akademik

  Database? _db;
  bool get isReady => _db != null;

  /// Nama BM/EN untuk label model. Dimuat sekali ke memori supaya skrin
  /// Kesan Objek tak perlu query database setiap frame.
  final Map<String, (String, String)> _labelNames = {};

  Database get _d {
    final db = _db;
    if (db == null) throw StateError('Database belum dibuka');
    return db;
  }

  // ============================== BUKA ==============================
  Future<void> init() async {
    if (_db != null) return;
    try {
      final dir = await getDatabasesPath();
      _db = await openDatabase(
        '$dir/$_fileName',
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      await _loadLabelNames();
      await _loadAcademicTerms();
      debugPrint('✅ Database dibuka: ${_labelNames.length} label objek');
    } catch (e) {
      debugPrint('❌ Ralat membuka database: $e');
      _db = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    final b = db.batch();
    b.execute('''
      CREATE TABLE users (
        id           TEXT PRIMARY KEY,
        email        TEXT NOT NULL,
        display_name TEXT,
        created_at   INTEGER NOT NULL
      )''');
    b.execute('''
      CREATE TABLE user_settings (
        user_id          TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        language         TEXT NOT NULL DEFAULT 'bm' CHECK (language IN ('bm','en')),
        speech_rate      REAL NOT NULL DEFAULT 1.0 CHECK (speech_rate BETWEEN 0.5 AND 1.5),
        theme_mode       TEXT NOT NULL DEFAULT 'system' CHECK (theme_mode IN ('system','light','dark')),
        vibrate          INTEGER NOT NULL DEFAULT 1 CHECK (vibrate IN (0,1)),
        auto_announce    INTEGER NOT NULL DEFAULT 1 CHECK (auto_announce IN (0,1)),
        speak_detections INTEGER NOT NULL DEFAULT 1 CHECK (speak_detections IN (0,1)),
        save_history     INTEGER NOT NULL DEFAULT 1 CHECK (save_history IN (0,1)),
        tutorial_seen    INTEGER NOT NULL DEFAULT 0 CHECK (tutorial_seen IN (0,1))
      )''');
    b.execute('''
      CREATE TABLE scan_history (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        title      TEXT NOT NULL,
        content    TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    b.execute('CREATE INDEX idx_scan_user_time ON scan_history(user_id, created_at DESC)');
    b.execute('''
      CREATE TABLE object_categories (
        id      INTEGER PRIMARY KEY,
        name_bm TEXT NOT NULL,
        name_en TEXT NOT NULL
      )''');
    b.execute('''
      CREATE TABLE object_labels (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id  INTEGER NOT NULL REFERENCES object_categories(id),
        model_source TEXT NOT NULL CHECK (model_source IN ('coco','campus')),
        model_key    TEXT NOT NULL,
        name_bm      TEXT NOT NULL,
        name_en      TEXT NOT NULL,
        UNIQUE (model_source, model_key)
      )''');

    for (final c in _kCategories) {
      b.insert('object_categories', {'id': c.$1, 'name_bm': c.$2, 'name_en': c.$3});
    }
    for (final l in _kCocoSeed) {
      b.insert('object_labels',
          {'category_id': l.$1, 'model_source': 'coco', 'model_key': l.$2, 'name_bm': l.$3, 'name_en': l.$4});
    }
    for (final l in _kCampusSeed) {
      b.insert('object_labels',
          {'category_id': _kCampusCategory, 'model_source': 'campus', 'model_key': l.$1, 'name_bm': l.$2, 'name_en': l.$3});
    }
    _createAcademic(b);
    await b.commit(noResult: true);
  }

  /// v3: perbendaharaan kata akademik BM <-> EN (skop proposal 1.5.1(5), Gantt 12.1).
  /// Digunakan untuk (1) memilih suara BM/EN yang betul semasa membaca nota,
  /// dan (2) skrin Istilah, yang menterjemah istilah dalam teks imbasan.
  void _createAcademic(Batch b) {
    b.execute('''
      CREATE TABLE academic_categories (
        id      INTEGER PRIMARY KEY,
        name_bm TEXT NOT NULL,
        name_en TEXT NOT NULL
      )''');
    b.execute('''
      CREATE TABLE academic_terms (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL REFERENCES academic_categories(id),
        term_bm     TEXT NOT NULL UNIQUE,
        term_en     TEXT NOT NULL UNIQUE
      )''');
    for (final c in _kAcademicCategories) {
      b.insert('academic_categories', {'id': c.$1, 'name_bm': c.$2, 'name_en': c.$3});
    }
    for (final t in _kAcademicSeed) {
      b.insert('academic_terms', {'category_id': t.$1, 'term_bm': t.$2, 'term_en': t.$3});
    }
  }

  /// Naik taraf database lama tanpa padam data pengguna.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN tutorial_seen INTEGER NOT NULL DEFAULT 0 '
          'CHECK (tutorial_seen IN (0,1))');
    }
    if (oldVersion < 3) {
      final b = db.batch();
      _createAcademic(b);
      await b.commit(noResult: true);
    }
  }

  // ============================ LABEL OBJEK ============================
  Future<void> _loadLabelNames() async {
    // campus dulu, kemudian coco tulis ganti (nama sama untuk chair/couch)
    final rows = await _d.query('object_labels',
        columns: ['model_key', 'name_bm', 'name_en'], orderBy: "model_source = 'coco'");
    _labelNames
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(
            r['model_key'] as String,
            (r['name_bm'] as String, r['name_en'] as String),
          )));
  }

  /// Nama paparan untuk label model (contoh: 'cell phone' -> 'Telefon').
  /// Kalau tiada dalam jadual: huruf besar di depan sahaja.
  String labelName(String key, {required bool bm}) {
    final n = _labelNames[key.toLowerCase()];
    if (n != null) return bm ? n.$1 : n.$2;
    return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1).toLowerCase();
  }

  // ========================== ISTILAH AKADEMIK ==========================
  final Map<String, AcademicTerm> _termByBm = {};
  final Map<String, AcademicTerm> _termByEn = {};

  Future<void> _loadAcademicTerms() async {
    final rows = await _d.rawQuery('''
      SELECT t.id, t.term_bm, t.term_en, c.name_bm AS cat_bm, c.name_en AS cat_en
      FROM academic_terms t JOIN academic_categories c ON c.id = t.category_id''');
    _termByBm.clear();
    _termByEn.clear();
    for (final r in rows) {
      final t = AcademicTerm(
        id: r['id'] as int,
        bm: r['term_bm'] as String,
        en: r['term_en'] as String,
        categoryBm: r['cat_bm'] as String,
        categoryEn: r['cat_en'] as String,
      );
      _termByBm[t.bm.toLowerCase()] = t;
      _termByEn[t.en.toLowerCase()] = t;
    }
  }

  static List<String> _tokens(String text) =>
      text.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();

  /// Istilah akademik dalam teks, ikut susunan muncul (tiada ulangan).
  /// Semak frasa dua perkataan dahulu (contoh "soal selidik"), kemudian satu perkataan.
  List<FoundTerm> findAcademicTerms(String text) {
    final w = _tokens(text);
    final seen = <int>{};
    final out = <FoundTerm>[];
    var i = 0;
    while (i < w.length) {
      FoundTerm? hit;
      var used = 1;
      if (i + 1 < w.length) {
        final two = '${w[i]} ${w[i + 1]}';
        hit = _match(two);
        if (hit != null) used = 2;
      }
      hit ??= _match(w[i]);
      if (hit != null && seen.add(hit.term.id)) out.add(hit);
      i += used;
    }
    return out;
  }

  FoundTerm? _match(String s) {
    final bm = _termByBm[s];
    if (bm != null) return FoundTerm(bm, foundInBm: true);
    final en = _termByEn[s];
    if (en != null) return FoundTerm(en, foundInBm: false);
    return null;
  }

  /// Bilangan istilah akademik BM dan EN dalam teks, untuk bantu pilih suara.
  (int, int) academicLanguageScore(String text) {
    var bm = 0, en = 0;
    for (final f in findAcademicTerms(text)) {
      f.foundInBm ? bm++ : en++;
    }
    return (bm, en);
  }

  // ============================== USERS ==============================
  /// Daftar / kemas kini pengguna. TIDAK guna REPLACE, sebab REPLACE padam
  /// baris lama dan CASCADE akan padam tetapan + sejarah.
  Future<void> upsertUser({required String id, required String email, String? displayName}) async {
    await _d.insert(
      'users',
      {'id': id, 'email': email, 'display_name': displayName, 'created_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _d.update('users', {'email': email, 'display_name': displayName}, where: 'id = ?', whereArgs: [id]);
  }

  /// Padam pengguna. ON DELETE CASCADE padam tetapan + semua sejarahnya.
  Future<void> deleteUser(String id) => _d.delete('users', where: 'id = ?', whereArgs: [id]);

  // ============================ USER_SETTINGS ============================
  Future<Map<String, Object?>?> getSettings(String userId) async {
    final rows = await _d.query('user_settings', where: 'user_id = ?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveSettings(String userId, Map<String, Object?> values) async {
    // user_settings tiada anak jadual, jadi REPLACE selamat di sini
    await _d.insert('user_settings', {...values, 'user_id': userId}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ============================ SCAN_HISTORY ============================
  /// CREATE
  Future<int> addScan({required String userId, required String title, required String content}) {
    final now = _now();
    return _d.insert('scan_history', {
      'user_id': userId,
      'title': title,
      'content': content,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// READ (terbaru di atas)
  Future<List<ScanRecord>> listScans(String userId) async {
    final rows = await _d.query('scan_history',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC, id DESC');
    return rows.map(ScanRecord.fromRow).toList();
  }

  /// UPDATE (namakan semula). Pulangkan true kalau berjaya.
  Future<bool> renameScan({required String userId, required int id, required String title}) async {
    final n = await _d.update('scan_history', {'title': title, 'updated_at': _now()},
        where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);
    return n == 1;
  }

  /// DELETE satu
  Future<bool> deleteScan({required String userId, required int id}) async {
    final n = await _d.delete('scan_history', where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);
    return n == 1;
  }

  /// DELETE semua milik pengguna ini
  Future<int> deleteAllScans(String userId) =>
      _d.delete('scan_history', where: 'user_id = ?', whereArgs: [userId]);

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}

// ============================== DATA AWAL ==============================
// Kategori ikut "supercategory" rasmi dataset COCO, + 1 untuk kampus.
const int _kCampusCategory = 13;
const List<(int, String, String)> _kCategories = [
  (1, 'Orang', 'Person'),
  (2, 'Kenderaan', 'Vehicle'),
  (3, 'Luar bangunan', 'Outdoor'),
  (4, 'Haiwan', 'Animal'),
  (5, 'Barang peribadi', 'Accessory'),
  (6, 'Sukan', 'Sports'),
  (7, 'Dapur', 'Kitchen'),
  (8, 'Makanan', 'Food'),
  (9, 'Perabot', 'Furniture'),
  (10, 'Elektronik', 'Electronic'),
  (11, 'Perkakas', 'Appliance'),
  (12, 'Barang dalam rumah', 'Indoor'),
  (_kCampusCategory, 'Kampus', 'Campus'),
];

// (kategori, kunci model COCO, BM, EN) — ikut susunan kelas YOLOv8 (0–79)
const List<(int, String, String, String)> _kCocoSeed = [
  (1, 'person', 'Orang', 'Person'),
  (2, 'bicycle', 'Basikal', 'Bicycle'),
  (2, 'car', 'Kereta', 'Car'),
  (2, 'motorcycle', 'Motosikal', 'Motorcycle'),
  (2, 'airplane', 'Kapal terbang', 'Airplane'),
  (2, 'bus', 'Bas', 'Bus'),
  (2, 'train', 'Kereta api', 'Train'),
  (2, 'truck', 'Lori', 'Truck'),
  (2, 'boat', 'Bot', 'Boat'),
  (3, 'traffic light', 'Lampu isyarat', 'Traffic light'),
  (3, 'fire hydrant', 'Pili bomba', 'Fire hydrant'),
  (3, 'stop sign', 'Papan tanda berhenti', 'Stop sign'),
  (3, 'parking meter', 'Meter letak kereta', 'Parking meter'),
  (3, 'bench', 'Bangku', 'Bench'),
  (4, 'bird', 'Burung', 'Bird'),
  (4, 'cat', 'Kucing', 'Cat'),
  (4, 'dog', 'Anjing', 'Dog'),
  (4, 'horse', 'Kuda', 'Horse'),
  (4, 'sheep', 'Biri-biri', 'Sheep'),
  (4, 'cow', 'Lembu', 'Cow'),
  (4, 'elephant', 'Gajah', 'Elephant'),
  (4, 'bear', 'Beruang', 'Bear'),
  (4, 'zebra', 'Zebra', 'Zebra'),
  (4, 'giraffe', 'Zirafah', 'Giraffe'),
  (5, 'backpack', 'Beg galas', 'Backpack'),
  (5, 'umbrella', 'Payung', 'Umbrella'),
  (5, 'handbag', 'Beg tangan', 'Handbag'),
  (5, 'tie', 'Tali leher', 'Tie'),
  (5, 'suitcase', 'Beg pakaian', 'Suitcase'),
  (6, 'frisbee', 'Frisbee', 'Frisbee'),
  (6, 'skis', 'Ski', 'Skis'),
  (6, 'snowboard', 'Papan salji', 'Snowboard'),
  (6, 'sports ball', 'Bola', 'Ball'),
  (6, 'kite', 'Layang-layang', 'Kite'),
  (6, 'baseball bat', 'Kayu besbol', 'Baseball bat'),
  (6, 'baseball glove', 'Sarung tangan besbol', 'Baseball glove'),
  (6, 'skateboard', 'Papan luncur', 'Skateboard'),
  (6, 'surfboard', 'Papan luncur air', 'Surfboard'),
  (6, 'tennis racket', 'Raket tenis', 'Tennis racket'),
  (7, 'bottle', 'Botol', 'Bottle'),
  (7, 'wine glass', 'Gelas', 'Glass'),
  (7, 'cup', 'Cawan', 'Cup'),
  (7, 'fork', 'Garpu', 'Fork'),
  (7, 'knife', 'Pisau', 'Knife'),
  (7, 'spoon', 'Sudu', 'Spoon'),
  (7, 'bowl', 'Mangkuk', 'Bowl'),
  (8, 'banana', 'Pisang', 'Banana'),
  (8, 'apple', 'Epal', 'Apple'),
  (8, 'sandwich', 'Sandwic', 'Sandwich'),
  (8, 'orange', 'Oren', 'Orange'),
  (8, 'broccoli', 'Brokoli', 'Broccoli'),
  (8, 'carrot', 'Lobak merah', 'Carrot'),
  (8, 'hot dog', 'Hot dog', 'Hot dog'),
  (8, 'pizza', 'Piza', 'Pizza'),
  (8, 'donut', 'Donat', 'Donut'),
  (8, 'cake', 'Kek', 'Cake'),
  (9, 'chair', 'Kerusi', 'Chair'),
  (9, 'couch', 'Sofa', 'Couch'),
  (9, 'potted plant', 'Pokok pasu', 'Potted plant'),
  (9, 'bed', 'Katil', 'Bed'),
  (9, 'dining table', 'Meja', 'Table'),
  (9, 'toilet', 'Tandas', 'Toilet'),
  (10, 'tv', 'TV', 'TV'),
  (10, 'laptop', 'Laptop', 'Laptop'),
  (10, 'mouse', 'Tetikus', 'Mouse'),
  (10, 'remote', 'Alat kawalan jauh', 'Remote'),
  (10, 'keyboard', 'Papan kekunci', 'Keyboard'),
  (10, 'cell phone', 'Telefon', 'Phone'),
  (11, 'microwave', 'Ketuhar gelombang mikro', 'Microwave'),
  (11, 'oven', 'Ketuhar', 'Oven'),
  (11, 'toaster', 'Pembakar roti', 'Toaster'),
  (11, 'sink', 'Sinki', 'Sink'),
  (11, 'refrigerator', 'Peti sejuk', 'Refrigerator'),
  (12, 'book', 'Buku', 'Book'),
  (12, 'clock', 'Jam', 'Clock'),
  (12, 'vase', 'Pasu bunga', 'Vase'),
  (12, 'scissors', 'Gunting', 'Scissors'),
  (12, 'teddy bear', 'Anak patung beruang', 'Teddy bear'),
  (12, 'hair drier', 'Pengering rambut', 'Hair dryer'),
  (12, 'toothbrush', 'Berus gigi', 'Toothbrush'),
];

// (kunci model kampus = campus_labels.txt huruf kecil, BM, EN)
const List<(String, String, String)> _kCampusSeed = [
  ('door', 'Pintu', 'Door'),
  ('cabinet door', 'Pintu kabinet', 'Cabinet door'),
  ('refrigerator door', 'Pintu peti sejuk', 'Refrigerator door'),
  ('window', 'Tingkap', 'Window'),
  ('chair', 'Kerusi', 'Chair'),
  ('table', 'Meja', 'Table'),
  ('cabinet', 'Kabinet', 'Cabinet'),
  ('couch', 'Sofa', 'Couch'),
  ('opened door', 'Pintu terbuka', 'Opened door'),
  ('pole', 'Tiang', 'Pole'),
];

// ============================ ISTILAH AKADEMIK ============================
// Istilah yang SAMA dalam BM dan EN (contoh "data", "formula") tidak
// dimasukkan: tiada terjemahan, dan tak membantu memilih suara.
const List<(int, String, String)> _kAcademicCategories = [
  (1, 'Penyelidikan', 'Research'),
  (2, 'Sains', 'Science'),
  (3, 'Matematik', 'Mathematics'),
  (4, 'Pengkomputeran', 'Computing'),
  (5, 'Pembelajaran', 'Learning'),
];

// (kategori, BM, EN)
const List<(int, String, String)> _kAcademicSeed = [
  // 1. Penyelidikan
  (1, 'kajian', 'study'),
  (1, 'penyelidikan', 'research'),
  (1, 'hipotesis', 'hypothesis'),
  (1, 'kaedah', 'method'),
  (1, 'metodologi', 'methodology'),
  (1, 'objektif', 'objective'),
  (1, 'skop', 'scope'),
  (1, 'dapatan', 'findings'),
  (1, 'kesimpulan', 'conclusion'),
  (1, 'pengenalan', 'introduction'),
  (1, 'abstrak', 'abstract'),
  (1, 'rujukan', 'reference'),
  (1, 'responden', 'respondent'),
  (1, 'soal selidik', 'questionnaire'),
  (1, 'temu bual', 'interview'),
  (1, 'sampel', 'sample'),
  (1, 'populasi', 'population'),
  (1, 'analisis', 'analysis'),
  (1, 'perbincangan', 'discussion'),
  (1, 'cadangan', 'recommendation'),
  (1, 'batasan', 'limitation'),
  (1, 'sorotan literatur', 'literature review'),
  (1, 'kerangka konsep', 'conceptual framework'),
  (1, 'pemboleh ubah', 'variable'),
  (1, 'signifikan', 'significant'),
  (1, 'instrumen', 'instrument'),
  (1, 'kebolehpercayaan', 'reliability'),
  (1, 'kesahan', 'validity'),
  (1, 'eksperimen', 'experiment'),
  (1, 'pemerhatian', 'observation'),
  // 2. Sains
  (2, 'sel', 'cell'),
  (2, 'tenaga', 'energy'),
  (2, 'daya', 'force'),
  (2, 'jisim', 'mass'),
  (2, 'halaju', 'velocity'),
  (2, 'pecutan', 'acceleration'),
  (2, 'suhu', 'temperature'),
  (2, 'tekanan', 'pressure'),
  (2, 'isipadu', 'volume'),
  (2, 'ketumpatan', 'density'),
  (2, 'tindak balas', 'reaction'),
  (2, 'unsur', 'element'),
  (2, 'sebatian', 'compound'),
  (2, 'molekul', 'molecule'),
  (2, 'organisma', 'organism'),
  (2, 'fotosintesis', 'photosynthesis'),
  (2, 'graviti', 'gravity'),
  (2, 'elektrik', 'electricity'),
  (2, 'gelombang', 'wave'),
  (2, 'cahaya', 'light'),
  // 3. Matematik
  (3, 'persamaan', 'equation'),
  (3, 'pecahan', 'fraction'),
  (3, 'perpuluhan', 'decimal'),
  (3, 'peratus', 'percentage'),
  (3, 'purata', 'average'),
  (3, 'sisihan piawai', 'standard deviation'),
  (3, 'kebarangkalian', 'probability'),
  (3, 'statistik', 'statistics'),
  (3, 'fungsi', 'function'),
  (3, 'graf', 'graph'),
  (3, 'jadual', 'table'),
  (3, 'kamiran', 'integral'),
  (3, 'pembezaan', 'differentiation'),
  (3, 'matriks', 'matrix'),
  (3, 'vektor', 'vector'),
  (3, 'sudut', 'angle'),
  (3, 'segi tiga', 'triangle'),
  (3, 'bulatan', 'circle'),
  (3, 'luas', 'area'),
  (3, 'nisbah', 'ratio'),
  (3, 'kadar', 'rate'),
  (3, 'teorem', 'theorem'),
  // 4. Pengkomputeran
  (4, 'algoritma', 'algorithm'),
  (4, 'pangkalan data', 'database'),
  (4, 'perisian', 'software'),
  (4, 'perkakasan', 'hardware'),
  (4, 'rangkaian', 'network'),
  (4, 'pengaturcaraan', 'programming'),
  (4, 'antara muka', 'interface'),
  (4, 'pelayan', 'server'),
  (4, 'pengguna', 'user'),
  (4, 'kata laluan', 'password'),
  (4, 'keselamatan', 'security'),
  (4, 'pengesahan', 'authentication'),
  (4, 'penyulitan', 'encryption'),
  (4, 'kecerdasan buatan', 'artificial intelligence'),
  (4, 'pembelajaran mesin', 'machine learning'),
  (4, 'sistem', 'system'),
  (4, 'aplikasi', 'application'),
  (4, 'storan', 'storage'),
  (4, 'memori', 'memory'),
  (4, 'pemproses', 'processor'),
  (4, 'skrin', 'screen'),
  (4, 'muat turun', 'download'),
  (4, 'muat naik', 'upload'),
  (4, 'reka bentuk', 'design'),
  (4, 'keperluan', 'requirement'),
  (4, 'pengujian', 'testing'),
  (4, 'penyahpepijatan', 'debugging'),
  // 5. Pembelajaran
  (5, 'kuliah', 'lecture'),
  (5, 'tugasan', 'assignment'),
  (5, 'peperiksaan', 'examination'),
  (5, 'kuiz', 'quiz'),
  (5, 'markah', 'marks'),
  (5, 'gred', 'grade'),
  (5, 'kursus', 'course'),
  (5, 'pensyarah', 'lecturer'),
  (5, 'penyelia', 'supervisor'),
  (5, 'fakulti', 'faculty'),
  (5, 'jabatan', 'department'),
  (5, 'universiti', 'university'),
  (5, 'perpustakaan', 'library'),
  (5, 'nota', 'notes'),
  (5, 'buku teks', 'textbook'),
  (5, 'bab', 'chapter'),
  (5, 'halaman', 'page'),
  (5, 'tarikh akhir', 'deadline'),
  (5, 'pembentangan', 'presentation'),
  (5, 'laporan', 'report'),
  (5, 'projek', 'project'),
  (5, 'kehadiran', 'attendance'),
  (5, 'jadual waktu', 'timetable'),
  (5, 'definisi', 'definition'),
  (5, 'contoh', 'example'),
  (5, 'ringkasan', 'summary'),
  (5, 'penerangan', 'explanation'),
  (5, 'soalan', 'question'),
  (5, 'jawapan', 'answer'),
];
