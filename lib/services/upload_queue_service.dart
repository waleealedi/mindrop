import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/recording_draft.dart';
import 'auth_service.dart';
import 'draft_store.dart';

/// عنوان الباك-إند المحلي أثناء التطوير.
///
/// الجهاز الفعلي (مو محاكي) يشوف "localhost" كنفسه هو، مو جهاز الماك.
/// عشان "localhost:8787" يشتغل من الجوال ويوصل فعليًا لباك-إند الماك،
/// لازم تسوي — مرة كل ما توصل الجهاز بالـ USB من جديد:
///
///   adb reverse tcp:8787 tcp:8787
///
/// هذا يسوي "نفق" عبر كيبل USB نفسه، يشتغل بدون أي اعتماد على شبكة واي
/// فاي مشتركة. لاحقًا لما يصير عندنا سيرفر منشور فعليًا، هذا الثابت وحده
/// اللي يتغيّر — مو أي كود ثاني بهذا الملف.
/// عنوان الباك-إند — يُحقن وقت البناء، ما يُعدَّل بالمصدر.
///
///   flutter run                      يستخدم الافتراضي (localhost + adb reverse)
///   `flutter build apk --dart-define=MINDROP_API_BASE=https://your-host`
///
/// الافتراضي محلي عمدًا: بناء التطوير يشتغل بدون أي إعداد، وبناء الإنتاج
/// يمرّر العنوان صراحةً. ما فيه مفتاح تبديل بالمصدر يتغيّر كل مرة.
const _baseUrl = String.fromEnvironment(
  'MINDROP_API_BASE',
  defaultValue: 'http://localhost:8787',
);

/// مهلة سخيّة عمدًا.
///
/// المستضيفات المجانية تنام بعد فترة خمول وتحتاج ~دقيقة تصحى. أول رفع بعد
/// خمول يقابل هذا الانتظار **قبل** ما يبدأ السيرفر يقرأ الطلب أصلًا.
///
/// حزمة `http` (1.6.0) ما تضع أي مهلة افتراضية على الطلب — تحقّقنا من
/// المصدر. يعني الطلب ينتظر بلا نهاية، وهذا سيف بحدّين: البرود ما يفشل
/// (زين)، لكن اتصالًا معلّقًا فعلًا يجمّد الطابور للأبد لأن `_isRunning`
/// ما يرجع false (شين). فنضع سقفًا يستوعب البرود بمريحة ويفكّ الطابور لو
/// علّق الاتصال.
const _uploadTimeout = Duration(minutes: 3);

/// طابور رفع بسيط: يقرأ كل التسجيلات اللي بانتظار الرفع من [DraftStore]
/// ويرفعها واحدة تلو الأخرى للباك-إند (multipart)، مع توكن Firebase
/// حقيقي بكل طلب.
///
/// ملاحظة مقصودة: لو وصلت دفعة رفع جديدة أثناء ما دفعة سابقة لسا شغالة،
/// الدفعة الجديدة تُتجاهل بصمت (مو تُجدول لبعدها) — أبسط شي يكفي MVP،
/// والمحاولة الجاية (فتح تطبيق، أو تسجيل جديد) بتلقط أي متبقي على أي حال.
class UploadQueueService {
  UploadQueueService._();
  static final UploadQueueService instance = UploadQueueService._();

  bool _isRunning = false;

  Future<void> processPendingUploads() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      final pending = await DraftStore.instance.pendingUpload();
      for (final draft in pending) {
        await _uploadOne(draft);
      }
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _uploadOne(RecordingDraft draft) async {
    draft.status = RecordingStatus.uploading;
    await DraftStore.instance.update(draft);

    try {
      final token = await AuthService.instance.getIdToken();
      final uri = Uri.parse('$_baseUrl/recordings/${draft.id}');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('audio', draft.filePath));

      final streamed = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw _UploadFailure(
          'فشل الرفع (${response.statusCode}): ${response.body}',
          // 5xx = السيرفر تعثّر أو لسا يصحى. مؤقت، يستاهل إعادة محاولة.
          // 4xx = طلب مرفوض فعلًا (توكن، تحقق) — إعادته ما تنفع.
          transient: response.statusCode >= 500,
        );
      }

      draft.status = RecordingStatus.uploaded;
      draft.errorMessage = null;
      await DraftStore.instance.update(draft);
    } catch (e) {
      // مؤقت للتشخيص: الفشل يُخزَّن بصمت بـ errorMessage محليًا (مو مرئي
      // بأي شاشة حاليًا)، فنطبعه هنا عشان يظهر مباشرة بتيرمنال flutter run.
      debugPrint('رفع التسجيل ${draft.id} فشل: $e');

      if (_isTransient(e)) {
        // **برود السيرفر انتظار، مو فشل.**
        //
        // نرجّع الحالة لـ recorded بدل failed: التسجيل يبقى داخل طابور
        // الانتظار، والشريحة تظل تقول "بانتظار الرفع"، وأي محفّز جاي
        // (فتح التطبيق، رجوع من الخلفية، ضغط الشريحة) يعيد المحاولة
        // تلقائيًا. وما نزيد retryCount — عدّاد المحاولات للفشل الحقيقي،
        // ولو حرقناه على كل نومة سيرفر لفقد معناه.
        draft.status = RecordingStatus.recorded;
        draft.errorMessage = null;
      } else {
        draft.status = RecordingStatus.failed;
        draft.retryCount += 1;
        draft.errorMessage = e.toString();
      }
      await DraftStore.instance.update(draft);
    }
  }

  /// فشل مؤقت = الشبكة أو السيرفر، مو الطلب نفسه.
  ///
  /// نغطي: انتهاء المهلة، وأخطاء المقبس/DNS ([SocketException] و
  /// [http.ClientException] اللي تنتج عن انقطاع الاتصال)، و5xx.
  bool _isTransient(Object e) {
    if (e is _UploadFailure) return e.transient;
    return e is TimeoutException ||
        e is SocketException ||
        e is http.ClientException ||
        e is HandshakeException;
  }
}

class _UploadFailure implements Exception {
  _UploadFailure(this.message, {required this.transient});
  final String message;
  final bool transient;
  @override
  String toString() => message;
}
