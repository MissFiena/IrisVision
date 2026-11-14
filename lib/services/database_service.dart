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
  static const int _version = 1;

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
      );
      await _loadLabelNames();
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
        save_history     INTEGER NOT NULL DEFAULT 1 CHECK (save_history IN (0,1))
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
    await b.commit(noResult: true);
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
