import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// توكنات الهوية البصرية لـ Mindrop — Dark Glassmorphism.
///
/// كل لون هنا مصدره وثيقة الرؤية التصميمية (انظر مستند
/// "رؤية-التصميم-Mindrop" داخل المشروع). لا تكتب ألوانًا مباشرة
/// داخل الواجهات — استخدم هذه الثوابت فقط عشان تبقى الهوية موحّدة.
class MindropColors {
  const MindropColors._();

  /// خلفية أساسية: أسود فحمي مطفي عميق.
  static const background = Color(0xFF0D0D0D);

  /// أساس الزجاج الداكن للبطاقات والحاويات.
  static const glass = Color(0xFF393939);

  /// اللون التفاعلي الأساسي: برتقالي متوهج (زر التسجيل).
  static const accent = Color(0xFFFF7A1A);
  static const accentSoft = Color(0xFFFFA24D);

  /// ألوان نيون ثانوية: تُستخدم للموجة الصوتية والعقد وصناديق الاختيار.
  static const neonTeal = Color(0xFF2EE6C5);
  static const neonBlue = Color(0xFF4C8DFF);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9A9AA0);

  /// حد فاتح شفاف يعطي حافة الزجاج بريقًا خفيفًا.
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);

  // ---------------------------------------------------------------------
  // نظام Stitch — "Bio-Digital Organic System".
  //
  // مصدرها تصدير Stitch الرسمي (`bio_digital_organic_system/DESIGN.md`)،
  // و**مقصورة على الخريطة الذهنية** حاليًا. خلفية النظام عند Stitch كحلية
  // (#0b1326) بينما خلفية Mindrop أسود محايد (#0D0D0D)؛ القرار كان الإبقاء
  // على الأسود بكل الشاشات، فناخذ لهجة العقد والتوهج فقط لا الخلفية.
  //
  // الأسماء تتبع أدوار Material اللي يصدّرها Stitch نفسه، مو أسماء لونية
  // وصفية: لو تغيّر التصدير لاحقًا يبقى الربط بين الطرفين واضحًا.
  //
  // (حلّت هذي محل `neonLime`/`neonPink` اللي أُضيفا بالجولة السابقة لتغطية
  // أربع فئات — Stitch يوفّر الأربع الآن، فالثابتان صارا بلا مبرّر.)
  // ---------------------------------------------------------------------

  /// primary — بنفسجي فاتح. فرع «الأفكار».
  static const stitchPrimary = Color(0xFFC0C1FF);

  /// primary-container — نيلي مشبع. **توهج الجذر وحده** — الجذر بلا لون حد
  /// (حدّه أبيض 10%)، فهويته اللونية كلها بالهالة.
  static const stitchPrimaryContainer = Color(0xFF8083FF);

  /// secondary — فيروزي. فرع «المهام».
  static const stitchSecondary = Color(0xFF44E2CD);

  /// tertiary — كهرماني. فرع «الأهداف».
  static const stitchTertiary = Color(0xFFF9BD22);

  /// on-surface — نص الجذر (أبيض مزرقّ، مو أبيض نقي).
  static const stitchOnSurface = Color(0xFFDAE2FD);

  /// on-surface-variant — نص العناصر.
  static const stitchOnSurfaceVariant = Color(0xFFC7C4D7);

  /// surface-container — تعبئة العقدة.
  static const stitchSurfaceContainer = Color(0xFF171F33);

  /// error — مرجانيّ. فرع «المواضيع».
  ///
  /// **ليش دور `error` كلون فرع:** تصدير Stitch يشحن ثلاث درجات لهجة فقط
  /// (secondary/tertiary/primary) ويدوّرها على العقد، بينما عندنا أربع فئات
  /// ثابتة. جرّبنا `primary-container` النيلي رابعًا فطلع قريبًا جدًا من
  /// `primary` البنفسجي: تسجيل فيه «أفكار + مواضيع» فقط — وهي أكثر تركيبة
  /// شائعة بالبيانات الحقيقية — كان يطلع أحادي اللون تمامًا.
  /// `error` هو الدرجة الوحيدة المتبقّية بالتصدير وهي متمايزة فعلًا، وما لها
  /// أي استعمال دلالي بالخريطة، فناخذها كلونٍ رابع لا كإشارة خطأ.
  static const stitchError = Color(0xFFFFB4AB);
}

/// خطوط الهوية — Geist للاتيني و IBM Plex Sans Arabic للعربي، حسب تصدير Stitch.
///
/// **نظام سكربتين مقصود:** Geist ما فيه محارف عربية أصلًا، فنمرّره عائلةً
/// أساسية ونحط العربي بـ `fontFamilyFallback`. المحرك يختار العائلة حسب
/// المحرف نفسه، فالجملة المخلوطة (عربي + إنجليزي بنفس السطر — وهي الحالة
/// الطبيعية عند مستخدم Mindrop) تطلع بكل سكربت على خطه بلا أي تبديل يدوي.
///
/// نخزّن الاسمين مرة واحدة: `GoogleFonts.x()` تبني `TextStyle` كامل بكل
/// نداء، والمطلوب هنا اسم العائلة فقط.
class MindropFonts {
  const MindropFonts._();

  static final String? latin = GoogleFonts.geist().fontFamily;
  static final String? arabic = GoogleFonts.ibmPlexSansArabic().fontFamily;

  /// قائمة الاحتياط جاهزة للتمرير لأي `TextStyle`.
  static final List<String> fallback = [if (arabic != null) arabic!];

  /// نمط نصي بالسكربتين — للرسم داخل `CustomPainter`.
  ///
  /// ضروري هناك تحديدًا: `TextPainter` ما يرث من شجرة الودجتس إطلاقًا، فأي
  /// `TextStyle` بلا `fontFamily` يطلع بخط النظام لا بخط الهوية. (كانت هذي
  /// حالة عقد الخريطة فعلًا قبل هذا التغيير.)
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
}

class MindropTheme {
  const MindropTheme._();

  /// يضيف العائلة العربية كاحتياط لكل مقاسات الثيم.
  ///
  /// `TextTheme.apply` يحافظ على `fontFamilyFallback` القائم، فترتيب
  /// الخطوتين (احتياط ثم ألوان) آمن.
  static TextTheme _dualScript(TextTheme geist) {
    TextStyle? f(TextStyle? s) =>
        s?.copyWith(fontFamilyFallback: MindropFonts.fallback);
    return TextTheme(
      displayLarge: f(geist.displayLarge),
      displayMedium: f(geist.displayMedium),
      displaySmall: f(geist.displaySmall),
      headlineLarge: f(geist.headlineLarge),
      headlineMedium: f(geist.headlineMedium),
      headlineSmall: f(geist.headlineSmall),
      titleLarge: f(geist.titleLarge),
      titleMedium: f(geist.titleMedium),
      titleSmall: f(geist.titleSmall),
      bodyLarge: f(geist.bodyLarge),
      bodyMedium: f(geist.bodyMedium),
      bodySmall: f(geist.bodySmall),
      labelLarge: f(geist.labelLarge),
      labelMedium: f(geist.labelMedium),
      labelSmall: f(geist.labelSmall),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: MindropColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MindropColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: MindropColors.background,
        primary: MindropColors.accent,
        secondary: MindropColors.neonTeal,
      ),
      // Geist + IBM Plex Sans Arabic. تُجلب أول مرة وتُخزَّن محليًا، وإذا
      // تعذّر ذلك يرجع Flutter لخط النظام بدون ما ينكسر شي.
      textTheme: _dualScript(GoogleFonts.geistTextTheme(base.textTheme)).apply(
        bodyColor: MindropColors.textPrimary,
        displayColor: MindropColors.textPrimary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF161616),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
