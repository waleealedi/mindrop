/// حالات معالجة التسجيل الصوتي — نفس تسلسل الحالات المتفق عليه في خطة الـ MVP:
/// recorded → uploading → uploaded → transcribing → analyzing → completed
/// وفي حالة الفشل بأي مرحلة: failed (مع إمكانية إعادة المحاولة Retry).
enum RecordingStatus {
  recorded,
  uploading,
  uploaded,
  transcribing,
  analyzing,
  completed,
  failed,
}

extension RecordingStatusProgress on RecordingStatus {
  /// موقع المرحلة على خط المعالجة. المصدر الوحيد لهذا الترتيب — أي مرحلة
  /// جديدة تُضاف هنا فقط، ولا تُشتق من جديد بأي مكان ثاني.
  ///
  /// [RecordingStatus.failed] ليست مرحلة على الخط، فتاخذ -1 وتُعالَج
  /// بقاعدة منفصلة في [mergedRecordingStatus].
  int get pipelineRank => switch (this) {
        RecordingStatus.recorded => 0,
        RecordingStatus.uploading => 1,
        RecordingStatus.uploaded => 2,
        RecordingStatus.transcribing => 3,
        RecordingStatus.analyzing => 4,
        RecordingStatus.completed => 5,
        RecordingStatus.failed => -1,
      };
}

/// يدمج الحالة المحلية مع الحالة السحابية ويرجّع الأصدق للعرض.
///
/// **ليش نحتاج دمجًا أصلًا:** أي طرف ممكن يتأخر عن الثاني.
/// - المحلي يعرف حقيقة التسجيل والرفع (المراحل 0–2) وحده.
/// - السحابي يعرف حقيقة المعالجة على السيرفر (3–5) وحده، **لكنه** يحمل
///   أيضًا كتابة قديمة بقيمة `recorded` تُسجَّل لحظة إنشاء المسودة قبل أي
///   رفع (انظر `FirestoreSyncService.syncMetadata`). فالسحابي ممكن يكون
///   **متأخرًا** عن المحلي، مو متقدمًا عليه دائمًا.
///
/// **قاعدة الفشل** (مقصودة بهذا الترتيب):
/// 1. `completed` يتغلّب على `failed`: الاكتمال دليل قاطع إن الخط كله نجح،
///    فما نخلي فشل قديم من محاولة سابقة (والإعادة مدعومة — انظر
///    `retryCount`) يخفي تسجيلًا خلّص فعلًا.
/// 2. عدا ذلك `failed` يتغلّب على أي مرحلة جارية: فشل ما يشوفه المستخدم
///    أسوأ خطأ ممكن هنا — يظن فكرته بأمان وهي ضايعة. وهذا يضمن كمان إن
///    قيمة `recorded` السحابية القديمة ما تخفي فشل رفع محلي حقيقي.
RecordingStatus mergedRecordingStatus(
  RecordingStatus local,
  RecordingStatus? remote,
) {
  if (remote == null) return local;

  if (local == RecordingStatus.completed ||
      remote == RecordingStatus.completed) {
    return RecordingStatus.completed;
  }
  if (local == RecordingStatus.failed || remote == RecordingStatus.failed) {
    return RecordingStatus.failed;
  }
  return local.pipelineRank >= remote.pipelineRank ? local : remote;
}

/// يمثّل تسجيلًا صوتيًا واحدًا (فكرة واحدة) محفوظًا محليًا، مع حالته
/// ضمن خط المعالجة. هذا الكائن هو مصدر الحقيقة المحلي — يُخزَّن في فهرس
/// JSON عبر [DraftStore] بحيث ما نفقد أي تسجيل حتى لو أُغلق التطبيق
/// أو انقطع الإنترنت أثناء الرفع.
class RecordingDraft {
  RecordingDraft({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.durationMs,
    this.status = RecordingStatus.recorded,
    this.retryCount = 0,
    this.errorMessage,
  });

  final String id;
  final String filePath;
  final DateTime createdAt;
  final int durationMs;

  RecordingStatus status;
  int retryCount;
  String? errorMessage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'status': status.name,
        'retryCount': retryCount,
        'errorMessage': errorMessage,
      };

  factory RecordingDraft.fromJson(Map<String, dynamic> json) {
    return RecordingDraft(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      durationMs: json['durationMs'] as int,
      status: RecordingStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RecordingStatus.recorded,
      ),
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
