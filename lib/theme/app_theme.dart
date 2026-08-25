import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// توكنات الهوية البصرية لـ Mindrop — **Obsidian Crimson**.
///
/// مصدر القيم: تصدير Stitch (`obsidian_crimson/DESIGN.md`). قبلها كانت
/// «Bio-Digital Organic» (نيلي/فيروزي/كهرماني على كحلي)، وقبلها أسود محايد
/// ببرتقالي. التحوّل كامل ومقصود، مو توسّع نطاق.
///
/// لا تكتب ألوانًا مباشرة داخل الودجتس — استخدم هذه الثوابت فقط.
class MindropColors {
  const MindropColors._();

  // ------------------------------------------------------------- الأسطح
  //
  // طبقتان لا طبقة واحدة: خلفية «فراغ» شبه سوداء، وسطح مرتفع أفتح فوقها.
  // قبل هذا كانت قيمة واحدة مسطّحة (#0D0D0D)، لأن التحوّل السابق كان
  // مقصورًا على عقد الخريطة ولا يشمل طلاء التطبيق كله.

  /// الطبقة القاعدية (Base Layer عند Stitch) — الفراغ اللي تطفو فوقه البقية.
  static const background = Color(0xFF0A0A0A);

  /// السطح المرتفع — ما تجلس عليه أغلب المكوّنات فعليًا.
  static const surface = Color(0xFF121414);

  /// أساس الزجاج الداكن للبطاقات والحاويات.
  static const glass = Color(0xFF393939);

  /// حد فاتح شفاف يعطي حافة الزجاج بريقًا خفيفًا.
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);

  // ------------------------------------------------------------- اللهجة
  //
  // Obsidian Crimson نظام **لهجة واحدة + محايدات**، بنفس نمط
  // primary/primary-container المستعمل من قبل.

  /// primary — قرمزي فاتح، آمن للنص والأيقونات على الأسود.
  static const crimsonPrimary = Color(0xFFFFB3B6);

  /// primary-container — القرمزي الحيّ: الأزرار والتوهج ونداءات الفعل.
  static const crimsonPrimaryContainer = Color(0xFFE11D48);

  /// on-surface — نص أساسي.
  static const crimsonOnSurface = Color(0xFFE3E2E2);

  /// on-surface-variant — نص ثانوي، فيه دفء ورديّ خفيف.
  static const crimsonOnSurfaceVariant = Color(0xFFE5BDBE);

  /// inverse-primary — قرمزي غامق مكتوم. الدرجة الثالثة بالعائلة، تحتاجها
  /// الموجة العضوية: ثلاثة أشرطة تحتاج ثلاث درجات متمايزة، والتصدير يوفّرها
  /// (`inverse-primary`) فما نخترع شيئًا.
  static const crimsonDeep = Color(0xFFBE0037);

  /// outline — حدود ومحايد.
  static const crimsonOutline = Color(0xFFAC8889);

  // -------------------------------------------------- ألوان الفئات الأربع
  //
  // **تسوية مقصودة، موثّقة عشان ما تُقرأ كإهمال.** التطبيق يحتاج أربع درجات
  // متمايزة (مهام/أهداف/أفكار/مواضيع)، وتصدير Crimson يوفّر لهجة واحدة
  // ومحايدَين رماديين **متطابقين** (#c8c6c5 لكل من secondary وtertiary).
  // فرض الرمادي على فئتين يلغي فائدة الترميز اللوني من أصله.
  //
  // فالنتيجة: اثنتان تبقيان على درجتَي Bio-Digital كما هما، والقرمزي ياخذ
  // «الأفكار». درجات Crimson حقيقية للاثنتين الباقيتين تحتاج تمريرة Stitch
  // جديدة — لا تُخترع هنا.

  /// فيروزي — فرع «المهام». من Bio-Digital، مُبقى عمدًا.
  static const categoryTeal = Color(0xFF44E2CD);

  /// كهرماني — فرع «الأهداف». من Bio-Digital، مُبقى عمدًا.
  static const categoryAmber = Color(0xFFF9BD22);

  /// ورديّ — فرع «المواضيع». **نفس القيمة بالتصديرين** (دور `error` عند
  /// الاثنين)، فما تغيّرت بالتحوّل إطلاقًا.
  static const categoryRose = Color(0xFFFFB4AB);

  /// أحمر رسائل الخطأ. كان مكتوبًا حرفيًا داخل شاشة التسجيل.
  static const errorRed = Color(0xFFFF6B6B);

  // ---------------------------------------------------------------- النص
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9A9AA0);
}

/// خطوط الهوية — Geist للاتيني، IBM Plex Sans Arabic للعربي،
/// JetBrains Mono للأرقام والطوابع الزمنية.
///
/// **ملاحظة على تاريخ القرار:** Geist طُبّق مرة ثم أُلغي بـ `5ecf9d5`، لأنه
/// دخل كتوسّع نطاق داخل مهمة محصورة بشاشة واحدة — لا لأن الخط مرفوض. الحين
/// هو جزء من تحوّل هوية كامل مصرّح به، والتعليق القديم اللي كان يشرح «ليش
/// Urbanist مو Geist» صار متجاوَزًا فأُزيل بدل ما يبقى يناقض الكود الحي.
///
/// **نظام سكربتين مقصود:** Geist ما فيه محارف عربية، فنمرّره عائلةً أساسية
/// ونحط العربي بـ `fontFamilyFallback`. المحرك يختار العائلة حسب المحرف
/// نفسه، فالجملة المخلوطة (عربي + إنجليزي بنفس السطر — وهي الحالة الطبيعية
/// عند مستخدم Mindrop) تطلع بكل سكربت على خطه بلا أي تبديل يدوي.
class MindropFonts {
  const MindropFonts._();

  static final String? latin = GoogleFonts.geist().fontFamily;
  static final String? arabic = GoogleFonts.ibmPlexSansArabic().fontFamily;

  /// أرقام وطوابع زمنية (`data-tabular` و`label-sm` عند Stitch).
  static final String? mono = GoogleFonts.jetBrainsMono().fontFamily;

  /// قائمة الاحتياط جاهزة للتمرير لأي `TextStyle`.
  static final List<String> fallback = [if (arabic != null) arabic!];

  /// زيادة ارتفاع السطر للعربي.
  ///
  /// تصدير Crimson ينصّ عليها صراحةً: العربية تحتاج ارتفاع سطر أكبر ~15%
  /// عشان ما تنقص التشكيلات من أعلى السطر. نطبّقها حيث نعرف اتجاه النص
  /// فعلًا وقت البناء.
  static const double rtlLineHeightBoost = 1.15;

  static double lineHeight(double base, bool isRtl) =>
      isRtl ? base * rtlLineHeightBoost : base;

  /// نمط نصي بالسكربتين — للرسم داخل `CustomPainter`.
  ///
  /// ضروري هناك تحديدًا: `TextPainter` ما يرث من شجرة الودجتس إطلاقًا، فأي
  /// `TextStyle` بلا `fontFamily` يطلع بخط النظام لا بخط الهوية.
  static TextStyle style({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: latin,
      fontFamilyFallback: fallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// نمط أرقام أحادي العرض — يمنع «رقص» التايمر بين إطار وإطار.
  static TextStyle monoStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: mono,
      fontFamilyFallback: fallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

class MindropTheme {
  const MindropTheme._();

  /// يضيف العائلة العربية كاحتياط لكل مقاسات الثيم.
  ///
  /// `TextTheme.apply` يحافظ على `fontFamilyFallback` القائم، فترتيب
  /// الخطوتين (احتياط ثم ألوان) آمن.
  static TextTheme _dualScript(TextTheme base) {
    TextStyle? f(TextStyle? s) =>
        s?.copyWith(fontFamilyFallback: MindropFonts.fallback);
    return TextTheme(
      displayLarge: f(base.displayLarge),
      displayMedium: f(base.displayMedium),
      displaySmall: f(base.displaySmall),
      headlineLarge: f(base.headlineLarge),
      headlineMedium: f(base.headlineMedium),
      headlineSmall: f(base.headlineSmall),
      titleLarge: f(base.titleLarge),
      titleMedium: f(base.titleMedium),
      titleSmall: f(base.titleSmall),
      bodyLarge: f(base.bodyLarge),
      bodyMedium: f(base.bodyMedium),
      bodySmall: f(base.bodySmall),
      labelLarge: f(base.labelLarge),
      labelMedium: f(base.labelMedium),
      labelSmall: f(base.labelSmall),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: MindropColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MindropColors.crimsonPrimaryContainer,
        brightness: Brightness.dark,
      ).copyWith(
        surface: MindropColors.surface,
        primary: MindropColors.crimsonPrimaryContainer,
        secondary: MindropColors.crimsonPrimary,
      ),
      // Geist + IBM Plex Sans Arabic. تُجلب أول مرة وتُخزَّن محليًا، وإذا
      // تعذّر ذلك يرجع Flutter لخط النظام بدون ما ينكسر شي.
      textTheme: _dualScript(GoogleFonts.geistTextTheme(base.textTheme)).apply(
        bodyColor: MindropColors.crimsonOnSurface,
        displayColor: MindropColors.crimsonOnSurface,
      ),
      dialogTheme: DialogThemeData(
        // كانت #161616 مكتوبة حرفيًا هنا.
        backgroundColor: MindropColors.surface,
        surfaceTintColor: Colors.transparent,
        // Crimson: بطاقات بزوايا 1rem بدل 24.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
