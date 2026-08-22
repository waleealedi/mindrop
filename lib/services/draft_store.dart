import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/recording_draft.dart';
import 'deletion_queue_service.dart';

/// يحفظ ملفات التسجيل الصوتي محليًا (مجلد recordings/) مع فهرس JSON بسيط
/// (drafts_index.json) لحالة كل تسجيل.
///
/// هذا الفهرس هو مصدر الحقيقة لطابور الرفع لاحقًا: أي مسودة حالتها
/// [RecordingStatus.recorded] أو [RecordingStatus.failed] تعتبر بانتظار
/// الرفع. بهذا التصميم يقدر المستخدم يقفل التطبيق أو يفقد الإنترنت أثناء
/// أي مرحلة بدون ما يضيع تسجيله.
class DraftStore {
  DraftStore._();
  static final DraftStore instance = DraftStore._();

  static const _indexFileName = 'drafts_index.json';
  static const _recordingsDirName = 'recordings';

  Directory? _appDir;
  final List<RecordingDraft> _drafts = [];
  bool _loaded = false;

  Future<Directory> _ensureAppDir() async {
    _appDir ??= await getApplicationDocumentsDirectory();
    return _appDir!;
  }

  Future<Directory> get _recordingsDir async {
    final dir = await _ensureAppDir();
    final recDir = Directory('${dir.path}/$_recordingsDirName');
    if (!await recDir.exists()) {
      await recDir.create(recursive: true);
    }
    return recDir;
  }

  Future<File> _indexFile() async {
    final dir = await _ensureAppDir();
    return File('${dir.path}/$_indexFileName');
  }

  /// يبني مسارًا جديدًا لملف تسجيل قبل بدء التسجيل الفعلي.
  Future<String> newRecordingPath(String id) async {
    final dir = await _recordingsDir;
    return '${dir.path}/$id.m4a';
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final file = await _indexFile();
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final list = jsonDecode(raw) as List<dynamic>;
        _drafts
          ..clear()
          ..addAll(
            list.map((e) => RecordingDraft.fromJson(e as Map<String, dynamic>)),
          );
      } catch (_) {
        // فهرس تالف (مثلاً بسبب إغلاق مفاجئ أثناء الكتابة) — نبدأ فهرس
        // نظيف بدل ما نكسر التطبيق بالكامل. ملفات الصوت نفسها ما تُحذف.
        _drafts.clear();
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final file = await _indexFile();
    final raw = jsonEncode(_drafts.map((d) => d.toJson()).toList());
    await file.writeAsString(raw);
  }

  Future<List<RecordingDraft>> all() async {
    await _ensureLoaded();
    return List.unmodifiable(_drafts);
  }

  /// كل التسجيلات اللي لسا ما انرفعت بنجاح — هذا هو "طابور الرفع".
  Future<List<RecordingDraft>> pendingUpload() async {
    await _ensureLoaded();
    return _drafts
        .where(
          (d) =>
              d.status == RecordingStatus.recorded ||
              d.status == RecordingStatus.failed,
        )
        .toList();
  }

  Future<void> add(RecordingDraft draft) async {
    await _ensureLoaded();
    _drafts.insert(0, draft);
    await _persist();
  }

  Future<void> update(RecordingDraft draft) async {
    await _ensureLoaded();
    final idx = _drafts.indexWhere((d) => d.id == draft.id);
    if (idx != -1) {
      _drafts[idx] = draft;
      await _persist();
    }
  }

  Future<void> remove(String id) async {
    await _ensureLoaded();
    final idx = _drafts.indexWhere((d) => d.id == id);
    if (idx == -1) return;

    // نيّة الحذف تُسجَّل **قبل** أي حذف محلي — راجع [DeletionQueueService]
    // لسبب هذا الترتيب. الحذف المحلي يتم فورًا وبدون انتظار الشبكة، فيبقى
    // العمل بلا إنترنت كما هو.
    await DeletionQueueService.instance.enqueue([id]);

    final draft = _drafts[idx];
    final file = File(draft.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    _drafts.removeAt(idx);
    await _persist();

    unawaited(DeletionQueueService.instance.flush());
  }

  /// يحذف كل التسجيلات دفعة وحدة: كل ملفات الصوت من القرص + تفريغ الفهرس.
  ///
  /// عمدًا ما يستدعي [remove] بحلقة — هذا كان راح يعيد كتابة الفهرس مع
  /// كل عنصر (I/O مكرر بلا داعي مع 26+ تسجيل). وعمدًا يلف كل حذف ملف
  /// بـ try/catch مستقل: لو فشل حذف ملف وحد (صلاحيات، أو كان محذوفًا
  /// مسبقًا) نكمل البقية بدل ما نوقف العملية ونسيب الفهرس بحالة
  /// نصف-محذوفة. الفهرس يتفرّغ دايمًا بالنهاية بغض النظر عن نتيجة كل ملف.
  Future<void> removeAll() async {
    await _ensureLoaded();

    // شواهد لكل المعرّفات قبل أي حذف، ثم دفعة سحابية واحدة عبر
    // [FirestoreSyncService.deleteRecordings] بدل N طلبات.
    await DeletionQueueService.instance.enqueue(_drafts.map((d) => d.id));

    for (final draft in _drafts) {
      try {
        final file = File(draft.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // نكمل حذف الباقي حتى لو فشل ملف وحد.
      }
    }
    _drafts.clear();
    await _persist();

    unawaited(DeletionQueueService.instance.flush());
  }
}
