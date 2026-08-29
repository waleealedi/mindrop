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
    this.title,
    this.titleEditedByUser = false,
    this.pinned = false,
  });

  final String id;
  final String filePath;
  final DateTime createdAt;
  final int durationMs;

  RecordingStatus status;
  int retryCount;
  String? errorMessage;

  /// عنوان التسجيل المحفوظ محليًا.
  ///
  /// `null` يعني ما فيه عنوان محلي — لا أن العنوان فاضي. العنوان الذي
  /// يولّده الذكاء يعيش بمستند Firestore وحده ولا يُنسخ هنا: نسخه يعني
  /// كتابة قرص إضافية لكل وصول تحليل، والنص المفرَّغ (البديل التالي
  /// بسلسلة العرض) سحابي أصلًا، فالغياب متطابق بالحالتين.
  String? title;

  /// هل كتب المستخدم هذا العنوان بيده؟
  ///
  /// حين تكون `true` لا يجوز لأي تحليل لاحق أن يستبدله — لا محليًا ولا
  /// بالباك-إند (انظر `saveAnalysis`). التسمية اليدوية نيّة صريحة، والعنوان
  /// المولَّد تخمين مهما كان جيدًا.
  bool titleEditedByUser;

  /// مثبَّت أعلى القائمة.
  ///
  /// المحلي هو مصدر الحقيقة هنا كبقية التطبيق؛ النسخة السحابية كتابة
  /// best-effort للنسخ الاحتياطي وحده، وما تُقرأ عند العرض. قراءتها كانت
  /// راح تخلي قيمة سحابية متأخرة تفكّ تثبيتًا فعله المستخدم للتو.
  bool pinned;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'status': status.name,
        'retryCount': retryCount,
        'errorMessage': errorMessage,
        'title': title,
        'titleEditedByUser': titleEditedByUser,
        'pinned': pinned,
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
      // فهرس قديم (سُجّل قبل هذي الميزة) ما فيه المفتاحين — الافتراضيات
      // تخلي كل تسجيل سابق يقرأ كـ«بلا عنوان»، وهو الصحيح تمامًا.
      title: json['title'] as String?,
      titleEditedByUser: json['titleEditedByUser'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}

/// العنوان المعروض لتسجيل واحد، أو `null` لو ما فيه عنوان بعد.
///
/// **سلسلة الأولوية، وليش بهذا الترتيب:**
/// 1. تسمية المستخدم اليدوية — نيّة صريحة، تتغلّب على كل شي دائمًا.
/// 2. عنوان الذكاء من التحليل السحابي.
/// 3. عنوان محلي غير يدوي، إن وُجد.
///
/// ترجّع `null` بدل نص بديل عمدًا: البديل (النص المفرَّغ المقصوص، ثم اسم
/// الحالة) قرار **عرض** يخص كل شاشة، وحشره هنا يجبر الشاشتين على نفس
/// الشكل. كل تسجيل قديم سُجّل قبل هذي الميزة يمر من هنا بـ `null` فيرجع
/// للسلوك السابق حرفيًا.
String? resolveRecordingTitle(RecordingDraft draft, String? remoteTitle) {
  String? clean(String? s) {
    final v = s?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  if (draft.titleEditedByUser) {
    final manual = clean(draft.title);
    if (manual != null) return manual;
  }
  return clean(remoteTitle) ?? clean(draft.title);
}
