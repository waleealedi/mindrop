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
}

class MindropTheme {
  const MindropTheme._();

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
      // Urbanist: خط الهوية. تُجلب النسخة أول مرة وتُخزَّن محليًا،
      // وإذا تعذّر ذلك يرجع Flutter تلقائيًا لخط النظام بدون ما ينكسر شي.
      textTheme: GoogleFonts.urbanistTextTheme(base.textTheme).apply(
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
