import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Hasil operasi auth: berjaya, atau mesej ralat yang selamat untuk dipaparkan.
class AuthResult {
  final bool ok;
  final String? message;
  const AuthResult.success()
      : ok = true,
        message = null;
  const AuthResult.failure(this.message) : ok = false;
}

/// Lapisan servis untuk Firebase Authentication.
///
/// Semua skrin (lapisan presentation) panggil kelas ni sahaja, bukan
/// FirebaseAuth terus. Kelebihan:
/// - Senang tukar backend nanti (contoh API sendiri) tanpa ubah UI.
/// - Semua mesej ralat diseragamkan di satu tempat.
/// - Senang diuji (boleh mock).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Tetapkan false hanya untuk demo/ujian dalaman.
  static const bool requireEmailVerification = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Stream status pengguna. Firebase simpan sesi secara automatik dalam
  /// storan peribadi app, jadi pengguna hanya perlu log masuk SEKALI.
  Stream<User?> userChanges() => _auth.userChanges();

  bool needsVerification(User user) => requireEmailVerification && !user.emailVerified;

  // --------------------------------------------------------------------------
  // DAFTAR
  // --------------------------------------------------------------------------
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user != null) {
        await user.updateDisplayName(name.trim());
        await _sendVerificationSafely(user);
        await user.reload();
      }
      return const AuthResult.success();
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_message(e, isRegister: true));
    } catch (e) {
      debugPrint('register error: $e');
      return const AuthResult.failure(_genericError);
    }
  }

  // --------------------------------------------------------------------------
  // LOG MASUK
  // --------------------------------------------------------------------------
  Future<AuthResult> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return const AuthResult.success();
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_message(e));
    } catch (e) {
      debugPrint('signIn error: $e');
      return const AuthResult.failure(_genericError);
    }
  }

  // --------------------------------------------------------------------------
  // LOG MASUK DENGAN GOOGLE
  // --------------------------------------------------------------------------
  /// Paling mudah untuk pengguna TalkBack: tiada kata laluan untuk ditaip,
  /// pilih akaun Google yang sudah ada dalam telefon. E-mel Google sudah
  /// disahkan, jadi tak perlu skrin "Sahkan E-mel".
  Future<AuthResult> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider()..addScope('email');
      await _auth.signInWithProvider(provider);
      return const AuthResult.success();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'web-context-canceled' || e.code == 'canceled' || e.code == 'popup-closed-by-user') {
        return const AuthResult.failure('Log masuk Google dibatalkan.');
      }
      if (e.code == 'account-exists-with-different-credential') {
        return const AuthResult.failure(
            'E-mel ini sudah didaftar dengan kata laluan. Sila log masuk dengan e-mel.');
      }
      return AuthResult.failure(_message(e));
    } catch (e) {
      debugPrint('google error: $e');
      return const AuthResult.failure(_genericError);
    }
  }

  // --------------------------------------------------------------------------
  // LUPA KATA LALUAN
  // --------------------------------------------------------------------------
  /// Sentiasa pulangkan "berjaya" untuk e-mel yang formatnya sah, walaupun
  /// e-mel tu tak wujud. Ini elak serangan "account enumeration"
  /// (penyerang teka e-mel mana yang berdaftar).
  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return const AuthResult.success();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return const AuthResult.success();
      if (e.code == 'network-request-failed' ||
          e.code == 'too-many-requests' ||
          e.code == 'invalid-email') {
        return AuthResult.failure(_message(e));
      }
      return const AuthResult.success();
    } catch (e) {
      debugPrint('reset error: $e');
      return const AuthResult.failure(_genericError);
    }
  }

  // --------------------------------------------------------------------------
  // PENGESAHAN E-MEL
  // --------------------------------------------------------------------------
  Future<AuthResult> resendVerification() async {
    final user = _auth.currentUser;
    if (user == null) return const AuthResult.failure(_genericError);
    try {
      await user.sendEmailVerification();
      return const AuthResult.success();
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_message(e));
    }
  }

  /// Muat semula status pengguna dari pelayan. Pulangkan true kalau e-mel
  /// dah disahkan.
  Future<bool> reloadAndCheckVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
    } catch (_) {
      // offline: guna status sedia ada
    }
    final verified = _auth.currentUser?.emailVerified ?? false;
    if (verified) {
      // paksa token baharu supaya tuntutan email_verified dikemas kini,
      // dan userChanges() beritahu AuthGate untuk tukar ke Home
      try {
        await _auth.currentUser?.getIdToken(true);
      } catch (_) {}
    }
    return verified;
  }

  /// Dipanggil sekali bila app dibuka. Kalau akaun dah dipadam / disekat
  /// oleh admin di Firebase Console, sesi lama dibatalkan.
  /// Kalau offline, abaikan — fungsi teras app mesti jalan tanpa internet.
  Future<void> validateSession() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.reload();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled' || e.code == 'user-not-found' || e.code == 'user-token-expired') {
        await signOut();
      }
    } catch (_) {
      // rangkaian tiada — teruskan dengan sesi tempatan
    }
  }

  Future<void> signOut() => _auth.signOut();

  // --------------------------------------------------------------------------
  // MESEJ RALAT
  // --------------------------------------------------------------------------
  static const String _genericError = 'Ralat tidak dijangka. Sila cuba lagi.';

  Future<void> _sendVerificationSafely(User user) async {
    try {
      await user.sendEmailVerification();
    } catch (e) {
      debugPrint('sendEmailVerification failed: $e');
    }
  }

  /// Mesej generik untuk log masuk: TIDAK beritahu sama ada e-mel wujud
  /// atau kata laluan salah (elak account enumeration).
  String _message(FirebaseAuthException e, {bool isRegister = false}) {
    switch (e.code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'wrong-password':
      case 'user-not-found':
        return 'E-mel atau kata laluan tidak betul.';
      case 'invalid-email':
        return 'Format e-mel tidak sah.';
      case 'user-disabled':
        return 'Akaun ini telah disekat. Sila hubungi pentadbir.';
      case 'email-already-in-use':
        return 'Tidak dapat mendaftar dengan e-mel ini. Cuba log masuk atau guna "Lupa kata laluan".';
      case 'weak-password':
      case 'password-does-not-meet-requirements':
        return 'Kata laluan terlalu lemah. Sila guna sekurang-kurangnya 8 aksara dengan huruf dan nombor.';
      case 'too-many-requests':
        return 'Terlalu banyak cubaan. Untuk keselamatan, sila tunggu beberapa minit dan cuba lagi.';
      case 'network-request-failed':
        return 'Tiada sambungan internet. Log masuk kali pertama memerlukan internet.';
      case 'operation-not-allowed':
        return 'Log masuk e-mel belum diaktifkan. Sila hubungi pentadbir.';
      default:
        debugPrint('FirebaseAuthException: ${e.code}');
        return _genericError;
    }
  }
}
