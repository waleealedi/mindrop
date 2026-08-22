import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'firestore_sync_service.dart';

/// طابور حذف سحابي دائم ("شواهد قبور").
///
/// ---------------------------------------------------------------------------
/// **ليش هذا مختلف عن سياسة الكتابة بالتطبيق كله.**
///
/// كل كتابة سحابية عندنا best-effort تفشل بصمت عمدًا (راجع
/// [FirestoreSyncService] و`bestEffort()` بالباك-إند)، عشان ما يتعطّل ولا
/// يضيع أي شغل محلي. هذي السياسة صحيحة **للكتابة**: أسوأ نتيجة لفشلها إن
/// السحابة تتأخر عن المحلي، والمحاولة الجاية تصلّحها.
///
/// الحذف يقلبها رأسًا على عقب. لو فشل الحذف السحابي بصمت، ينمحي السجل
/// المحلي وتبقى النسخة السحابية موجودة **بلا أي طريق يوصل لها**: المستخدم
/// ما عاد يشوف الشيء اللي يبي يحذفه، فما يقدر يعيد المحاولة. الصمت هنا
/// هو العيب نفسه، مو تخفيفًا له.
///
/// وبنفس الوقت ما نقدر نحذف من السحابة أولًا ثم محليًا: التطبيق محلي-أولًا
/// ولازم الحذف يشتغل بدون شبكة ويحس فوريًا.
///
/// **الحل: نية حذف دائمة.** نكتب معرّف التسجيل بملف على القرص **قبل** ما
/// نحذفه محليًا، ثم نحاول الحذف السحابي. لو نجح نشيل الشاهد، ولو فشل يبقى
/// ويُعاد تلقائيًا على نفس محفّزات الرفع (فتح التطبيق، الرجوع له، أو بعد
/// كل جولة رفع). فما فيه لحظة وحدة يصير فيها مستند سحابي بلا سجل بنيّة
/// حذفه — وهذا بالضبط تعريف اليتيم اللي نمنعه.
/// ---------------------------------------------------------------------------
class DeletionQueueService {
  DeletionQueueService._();
  static final DeletionQueueService instance = DeletionQueueService._();

  static const _fileName = 'pending_deletions.json';

  Directory? _appDir;
  List<String>? _pending;
  bool _isRunning = false;

  Future<File> _file() async {
    _appDir ??= await getApplicationDocumentsDirectory();
    return File('${_appDir!.path}/$_fileName');
  }

  Future<List<String>> _load() async {
    if (_pending != null) return _pending!;
    final file = await _file();
    if (!await file.exists()) return _pending = <String>[];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return _pending = raw.whereType<String>().toList();
    } catch (_) {
      // ملف تالف: نبدأ نظيفًا بدل ما نكسر الحذف كليًا.
      return _pending = <String>[];
    }
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_pending ?? const <String>[]));
  }

  /// يسجّل نيّة حذف. **يُنادى قبل الحذف المحلي**، لا بعده: لو انقطع
  /// التطبيق بين الاثنين، الشاهد موجود فيُستكمل الحذف لاحقًا. العكس
  /// (محلي ثم شاهد) يترك يتيمًا لو صار الانقطاع بينهما.
  Future<void> enqueue(Iterable<String> recordingIds) async {
    final pending = await _load();
    for (final id in recordingIds) {
      if (!pending.contains(id)) pending.add(id);
    }
    await _persist();
  }

  int get pendingCount => _pending?.length ?? 0;

  /// يحاول تنفيذ كل عمليات الحذف المعلّقة.
  ///
  /// ما يرمي أبدًا: يُنادى من محفّزات خلفية. لكن **ما يشيل الشاهد إلا
  /// عند نجاح مؤكَّد** — أي فشل يبقيه للمحاولة الجاية.
  Future<void> flush() async {
    // نفس حارس [UploadQueueService]: يُضبط قبل أي await فما تتسابق نداءتان.
    if (_isRunning) return;
    _isRunning = true;
    try {
      final pending = await _load();
      if (pending.isEmpty) return;

      final ids = List<String>.from(pending);
      try {
        // مهلة مقصودة: `batch.commit()` بلا شبكة **ما يرمي** — Firestore
        // يخزّن الكتابة محليًا ويبقي الـ Future معلّقًا لين يؤكّدها الخادم.
        // بدون سقف هنا يعلق `_isRunning` على true للأبد فتموت كل محاولة
        // لاحقة بهذي الجلسة.
        //
        // انتهاء المهلة ما يعني ضياع الحذف: الشاهد يبقى، وطابور Firestore
        // نفسه يعيد إرسال الحذف أول ما ترجع الشبكة. وحذف مستند محذوف
        // أصلًا عملية لا-أثر لها، فإعادة المحاولة آمنة تمامًا.
        await FirestoreSyncService.instance
            .deleteRecordings(ids)
            .timeout(const Duration(seconds: 20));
        _pending!.removeWhere(ids.contains);
        await _persist();
      } catch (e) {
        // فشل متوقّع بلا شبكة. الشواهد تبقى، والمحاولة الجاية تلقطها.
        debugPrint('حذف سحابي معلّق (${ids.length}) لسا ما نجح: $e');
      }
    } finally {
      _isRunning = false;
    }
  }
}
