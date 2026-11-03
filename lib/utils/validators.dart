import '../services/lang.dart';

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
    if (v.isEmpty) return t('Sila masukkan nama penuh.', 'Please enter your full name.');
    if (v.length < 2) return t('Nama terlalu pendek.', 'Name is too short.');
    if (v.length > nameMax) return t('Nama maksimum $nameMax aksara.', 'Name can be at most $nameMax characters.');
    if (!_name.hasMatch(v)) return t('Nama hanya boleh mengandungi huruf.', 'Name can only contain letters.');
    return null;
  }

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return t('Sila masukkan e-mel.', 'Please enter your email.');
    if (v.length > 254 || !_email.hasMatch(v)) {
      return t('Format e-mel tidak sah. Contoh: nama@gmail.com', 'Invalid email format. Example: name@gmail.com');
    }
    return null;
  }

  /// Untuk skrin log masuk: cuma pastikan tak kosong. Jangan dedahkan
  /// polisi kata laluan di sini.
  static String? loginPassword(String? value) {
    if ((value ?? '').isEmpty) return t('Sila masukkan kata laluan.', 'Please enter your password.');
    return null;
  }

  /// Untuk daftar akaun baharu.
  static String? newPassword(String? value, {String? email}) {
    final v = value ?? '';
    if (v.isEmpty) return t('Sila cipta kata laluan.', 'Please create a password.');
    if (v.length < passwordMin) {
      return t('Kata laluan mesti sekurang-kurangnya $passwordMin aksara.', 'Password must be at least $passwordMin characters.');
    }
    if (v.length > passwordMax) {
      return t('Kata laluan maksimum $passwordMax aksara.', 'Password can be at most $passwordMax characters.');
    }
    if (v.trim() != v) return t('Kata laluan tidak boleh bermula atau berakhir dengan ruang.', 'Password cannot start or end with a space.');
    if (_commonPasswords.contains(v.toLowerCase())) {
      return t('Kata laluan ini terlalu biasa dan mudah diteka. Sila pilih yang lain.', 'This password is too common and easy to guess. Please choose another.');
    }
    final localPart = (email ?? '').split('@').first.toLowerCase();
    if (localPart.length >= 4 && v.toLowerCase().contains(localPart)) {
      return t('Kata laluan tidak boleh mengandungi nama e-mel anda.', 'Password cannot contain your email name.');
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
      return t('Kata laluan mesti ada sekurang-kurangnya satu huruf dan satu nombor.', 'Password needs at least one letter and one number.');
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return t('Sila taip semula kata laluan.', 'Please type your password again.');
    if (value != original) return t('Kata laluan tidak sama.', 'Passwords do not match.');
    return null;
  }
}
