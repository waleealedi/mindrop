import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/recording_draft.dart';
import 'auth_service.dart';

/// مزامنة "بيانات وصفية فقط" (metadata) لكل تسجيل مع Firestore — عمدًا
/// بدون رفع ملف الصوت نفسه:
/// - Firebase Storage معطّل مؤقتًا (مشكلة فوترة Blaze لسا ما انحلّت).
/// - الباك-إند اللي بيستقبل الصوت (Node.js، المرحلة 2) لسا ما اتبنى.
///
/// الفايدة الحالية: نسخة سحابية خفيفة من "قائمة الأفكار" (id/تاريخ/مدة/
/// حالة) حتى قبل ما يكون عندنا رفع صوت حقيقي، وأساس جاهز نبني عليه
/// بدون تغيير شكل البيانات لاحقًا.
///
/// ⚠️ الفهرس المحلي (DraftStore) يبقى مصدر الحقيقة دائمًا. هذي المزامنة
/// best-effort فقط — أي فشل (لا إنترنت مثلًا) يُتجاهل ولا يوقف التسجيل.
class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

  Future<CollectionReference<Map<String, dynamic>>> _recordingsRef() async {
    final uid = await AuthService.instance.ensureSignedIn();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('recordings');
  }

  Future<void> syncMetadata(RecordingDraft draft) async {
    final ref = await _recordingsRef();
    await ref.doc(draft.id).set({
      'createdAt': draft.createdAt.toIso8601String(),
      'durationMs': draft.durationMs,
      'status': draft.status.name,
      'retryCount': draft.retryCount,
      'errorMessage': draft.errorMessage,
    }, SetOptions(merge: true));
  }

  /// يحذف مستندات تسجيلات من السحابة.
  ///
  /// **يرمي عند الفشل عمدًا** — بعكس [syncMetadata] الـ best-effort. الحذف
  /// لازم يعرف المستدعي نتيجته عشان يقرر يبقي الشاهد أو يشيله
  /// (انظر `DeletionQueueService`). ابتلاع الخطأ هنا = يتيم دائم.
  ///
  /// نستخدم [WriteBatch]: التزام واحد ذرّي بدل N طلبات شبكة منفصلة.
  ///
  /// **الحدود الفعلية** (من وثائق Firestore الحالية): ما فيه سقف منصوص
  /// لعدد العمليات بالدفعة — السقف العملي هو **حجم الطلب 10 MiB**
  /// (والـ500 المشهورة اليوم تخص «تحويلات الحقول للمستند الواحد»، مو عدد
  /// العمليات). حذف المستند حمولته مساره فقط، فـ10 MiB تكفي آلافًا. مع ذلك
  /// نقسّم على دفعات محافِظة: هامش أمان أمام سقف الحجم، وأمام أي واجهة
  /// خلفية لسا تفرض الـ500 القديمة.
  Future<void> deleteRecordings(List<String> recordingIds) async {
    if (recordingIds.isEmpty) return;
    final ref = await _recordingsRef();
    const chunkSize = 400;

    for (var i = 0; i < recordingIds.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, recordingIds.length);
      final batch = FirebaseFirestore.instance.batch();
      for (final id in recordingIds.sublist(i, end)) {
        batch.delete(ref.doc(id));
      }
      await batch.commit();
    }
  }

  /// ما يكتبه الباك-إند بعد التفريغ: النص وحالة المعالجة الحقيقية.
  ///
  /// نفصله عن [RecordingDraft] عمدًا — المسودة المحلية تبقى مصدر الحقيقة
  /// للتسجيل نفسه، وهذا مجرد "طبقة سحابية" تُدمج فوقها عند العرض.
  Future<Stream<Map<String, RemoteRecording>>> watchRemote() async {
    final ref = await _recordingsRef();
    return ref.snapshots().map((snap) {
      final out = <String, RemoteRecording>{};
      for (final doc in snap.docs) {
        out[doc.id] = RemoteRecording.fromMap(doc.data());
      }
      return out;
    });
  }
}

/// نسخة القراءة من مستند التسجيل بـ Firestore.
class RemoteRecording {
  const RemoteRecording({
    this.transcript,
    this.status,
    this.errorMessage,
    this.analysis,
  });

  final String? transcript;
  final RecordingStatus? status;
  final String? errorMessage;
  final RecordingAnalysis? analysis;

  bool get hasTranscript => (transcript?.trim().isNotEmpty ?? false);

  factory RemoteRecording.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status'] as String?;
    final rawAnalysis = map['analysis'];
    return RemoteRecording(
      transcript: map['transcript'] as String?,
      // حالة غير معروفة (نسخة أحدث من الباك-إند مثلًا) نتجاهلها بدل ما
      // نرمي استثناء ونكسر القائمة كاملة.
      status:
          RecordingStatus.values.where((s) => s.name == rawStatus).firstOrNull,
      errorMessage: map['errorMessage'] as String?,
      analysis: rawAnalysis is Map<String, dynamic>
          ? RecordingAnalysis.fromMap(rawAnalysis)
          : null,
    );
  }
}

/// المحتوى المنظّم المستخرَج من النص المفرَّغ.
///
/// كل الحقول مصفوفات نصوص وقد تكون فاضية — تسجيل قصير بلا مهام نتيجة
/// صحيحة تمامًا، مو نقص بالبيانات.
class RecordingAnalysis {
  const RecordingAnalysis({
    required this.tasks,
    required this.goals,
    required this.ideas,
    required this.topics,
  });

  final List<String> tasks;
  final List<String> goals;
  final List<String> ideas;
  final List<String> topics;

  bool get isEmpty =>
      tasks.isEmpty && goals.isEmpty && ideas.isEmpty && topics.isEmpty;

  static List<String> _strings(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  factory RecordingAnalysis.fromMap(Map<String, dynamic> map) {
    return RecordingAnalysis(
      tasks: _strings(map['tasks']),
      goals: _strings(map['goals']),
      ideas: _strings(map['ideas']),
      topics: _strings(map['topics']),
    );
  }
}
