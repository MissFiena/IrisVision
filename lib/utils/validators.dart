/// Validasi input di sisi klien.
///
/// Nota keselamatan: validasi klien hanya untuk UX (mesej cepat & jelas).
/// Kawalan sebenar tetap di pelayan Firebase Auth (format e-mel, polisi
/// kata laluan, had cubaan). Jangan anggap validasi klien sebagai kawalan
/// keselamatan.
class Validators {
  Validators._();

  static const int nameMax = 60;
  static const int passwordMin = 8; // NIST SP 800-63B: minimum 8
  static const int passwordMax = 64; // NIST: benarkan sekurang-kurangnya 64

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _name = RegExp(r"^[A-Za-zÀ-ɏ' .@/-]+$");

  /// Senarai ringkas kata laluan paling biasa (NIST: sekat kata laluan
  /// yang diketahui lemah / pernah bocor).
  static const Set<String> _commonPasswords = {
    '12345678', '123456789', '1234567890', '11111111', '00000000',
    'password', 'password1', 'password123', 'qwerty123', 'qwertyuiop',
    'abc12345', 'abcd1234', 'iloveyou', 'sayang123', 'malaysia',
    'malaysia1', 'upsi1234', 'irisvision', 'admin123', 'welcome1',
    'aaaaaaaa', '87654321', '12341234', 'asdfghjk', 'zxcvbnm1',
  };

  static String? name(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Sila masukkan nama penuh.';
    if (v.length < 2) return 'Nama terlalu pendek.';
    if (v.length > nameMax) return 'Nama maksimum $nameMax aksara.';
    if (!_name.hasMatch(v)) return 'Nama hanya boleh mengandungi huruf.';
    return null;
  }

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Sila masukkan e-mel.';
    if (v.length > 254 || !_email.hasMatch(v)) {
      return 'Format e-mel tidak sah. Contoh: nama@gmail.com';
    }
    return null;
  }

  /// Untuk skrin log masuk: cuma pastikan tak kosong. Jangan dedahkan
  /// polisi kata laluan di sini.
  static String? loginPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Sila masukkan kata laluan.';
    return null;
  }

  /// Untuk daftar akaun baharu.
  static String? newPassword(String? value, {String? email}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Sila cipta kata laluan.';
    if (v.length < passwordMin) {
      return 'Kata laluan mesti sekurang-kurangnya $passwordMin aksara.';
    }
    if (v.length > passwordMax) {
      return 'Kata laluan maksimum $passwordMax aksara.';
    }
    if (v.trim() != v) return 'Kata laluan tidak boleh bermula atau berakhir dengan ruang.';
    if (_commonPasswords.contains(v.toLowerCase())) {
      return 'Kata laluan ini terlalu biasa dan mudah diteka. Sila pilih yang lain.';
    }
    final localPart = (email ?? '').split('@').first.toLowerCase();
    if (localPart.length >= 4 && v.toLowerCase().contains(localPart)) {
      return 'Kata laluan tidak boleh mengandungi nama e-mel anda.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Kata laluan mesti ada sekurang-kurangnya satu huruf dan satu nombor.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Sila taip semula kata laluan.';
    if (value != original) return 'Kata laluan tidak sama.';
    return null;
  }
}
