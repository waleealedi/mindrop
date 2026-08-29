// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get hintIdle => 'اضغط وابدأ الكلام';

  @override
  String get hintRecording => 'جارٍ التسجيل — اضغط للإيقاف';

  @override
  String get hintPaused => 'متوقف مؤقتًا — اضغط للمتابعة';

  @override
  String get recordStatusIdle => 'جاهز لالتقاط فكرتك…';

  @override
  String get recordStatusRecording => 'أسمعك…';

  @override
  String get recordStatusPaused => 'بانتظارك';

  @override
  String get savedLocally => 'تم حفظ فكرتك محليًا';

  @override
  String get recordStartFailed => 'تعذّر بدء التسجيل، حاول مرة ثانية';

  @override
  String get recordNotSaved => 'لم يتم حفظ التسجيل';

  @override
  String get micPermissionTitle => 'نحتاج إذن المايك';

  @override
  String get micPermissionRationale =>
      'Mindrop يحتاج الوصول للمايك عشان تقدر تلتقط أفكارك بصوتك.';

  @override
  String get micPermissionBlocked =>
      'صلاحية المايك مرفوضة بشكل دائم. افتح إعدادات التطبيق لتفعيلها.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get allow => 'سماح';

  @override
  String get openSettings => 'فتح الإعدادات';

  @override
  String get uploadRetrying => 'جارٍ إعادة محاولة الرفع…';

  @override
  String pendingUploads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تسجيل بانتظار الرفع',
      many: '$count تسجيلًا بانتظار الرفع',
      few: '$count تسجيلات بانتظار الرفع',
      two: 'تسجيلان بانتظار الرفع',
      one: 'تسجيل واحد بانتظار الرفع',
      zero: 'لا شيء بانتظار الرفع',
    );
    return '$_temp0';
  }

  @override
  String get historyTitle => 'أفكارك';

  @override
  String get historyToday => 'اليوم';

  @override
  String get historyYesterday => 'أمس';

  @override
  String get historyEmpty => 'لسا ما سجّلت أي فكرة';

  @override
  String get historyOpenTooltip => 'عرض الأفكار المسجّلة';

  @override
  String get statusRecorded => 'بانتظار الرفع';

  @override
  String get statusUploading => 'جارِ الرفع';

  @override
  String get statusUploaded => 'تم الرفع';

  @override
  String get statusTranscribing => 'جارِ التفريغ';

  @override
  String get statusAnalyzing => 'جارِ التحليل';

  @override
  String get statusCompleted => 'مكتمل';

  @override
  String get statusFailed => 'فشل الرفع';

  @override
  String get delete => 'حذف';

  @override
  String get deleteConfirmTitle => 'تحذف هذي الفكرة؟';

  @override
  String get deleteConfirmBody =>
      'التسجيل ونصّه المفرَّغ بينحذفون نهائيًا من جهازك ومن السحابة.';

  @override
  String get deleteAll => 'حذف الكل';

  @override
  String get deleteAllConfirmTitle => 'تحذف كل الأفكار؟';

  @override
  String get deleteAllConfirmBody =>
      'كل التسجيلات ونصوصها المفرَّغة بتنحذف نهائيًا من جهازك ومن السحابة. ما فيه تراجع.';

  @override
  String get playbackLoadError => 'تعذّر تحميل هذا التسجيل';

  @override
  String get transcriptPending =>
      'لسا ما فيه تفريغ — بيظهر هنا أول ما تخلص المعالجة';

  @override
  String get analysisTasks => 'مهام';

  @override
  String get analysisGoals => 'أهداف';

  @override
  String get analysisIdeas => 'أفكار';

  @override
  String get analysisTopics => 'مواضيع';

  @override
  String get analysisEmpty => 'ما فيه شي نستخرجه من هذا التسجيل';

  @override
  String get mindMapTitle => 'الخريطة الذهنية';

  @override
  String get mindMapOpen => 'عرض الخريطة الذهنية';

  @override
  String get mindMapEmpty =>
      'ما فيه شي نرسمه بعد — الخريطة تظهر أول ما يتنظّم هذا التسجيل';

  @override
  String get mindMapRecordingNode => 'التسجيل';

  @override
  String get mindMapResetView => 'إعادة توسيط الخريطة';

  @override
  String get analysisPending => 'جارِ تنظيم الفكرة…';

  @override
  String get recordingActions => 'خيارات التسجيل';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get renameTitle => 'إعادة تسمية التسجيل';

  @override
  String get renameHint => 'العنوان';

  @override
  String get save => 'حفظ';

  @override
  String get share => 'مشاركة';

  @override
  String get shareNothingYet =>
      'ما فيه شي نشاركه بعد — هذا التسجيل بلا نص مفرَّغ';

  @override
  String get pin => 'تثبيت';

  @override
  String get unpin => 'إلغاء التثبيت';

  @override
  String get historyPinned => 'المثبَّتة';

  @override
  String get a11yStartRecording => 'بدء التسجيل';

  @override
  String get a11yStopRecording => 'إيقاف التسجيل';

  @override
  String get a11yPlayRecording => 'تشغيل التسجيل';

  @override
  String get a11yPauseRecording => 'إيقاف التشغيل مؤقتًا';
}
