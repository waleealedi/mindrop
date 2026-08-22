import 'package:firebase_auth/firebase_auth.dart';

/// تسجيل دخول مجهول (Anonymous) بدون أي شاشة تسجيل — كل جهاز يحصل على
/// uid ثابت تلقائيًا، بما يتماشى مع مبدأ "افتح التطبيق وابدأ الكلام"
/// (بدون أي احتكاك قبل أول تسجيل).
///
/// ⚠️ best-effort: لو ما فيه إنترنت، ensureSignedIn() ترمي خطأ ويُلتقط
/// من المستدعي (راجع FirestoreSyncService) — التسجيل المحلي يستمر
/// يشتغل طبيعي بدون أي اعتماد على تسجيل الدخول.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  Future<String> ensureSignedIn() async {
    final current = _auth.currentUser;
    if (current != null) return current.uid;

    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('فشل تسجيل الدخول المجهول: لا يوجد مستخدم بعد النجاح.');
    }
    return user.uid;
  }

  /// توكن Firebase الحالي (JWT) — يُرسل للباك-إند بـ Authorization header
  /// عشان يتحقق من هويتنا الحقيقية بنفسه (verifyIdToken)، بدل ما يصدّق
  /// أي uid نرسله كنص عادي.
  Future<String> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('ما فيه مستخدم مسجّل دخول — نادِ ensureSignedIn() أول.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw StateError('فشل الحصول على توكن من Firebase.');
    }
    return token;
  }
}
