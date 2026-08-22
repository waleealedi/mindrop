import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/record_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // شريط الحالة وشريط التنقل يذوبان بالخلفية السوداء بدل ما يقطعان
  // التصميم بشريط رمادي فوق وتحت.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: MindropColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Firebase اختياري لعمل التطبيق: لو فشلت التهيئة (مثلاً أول تشغيل
  // بدون إنترنت) يستمر التسجيل الصوتي المحلي طبيعي بدون أي مزامنة
  // سحابية لين يتوفر الاتصال.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed — التطبيق مستمر محليًا فقط: $e');
  }

  runApp(const MindropApp());
}

class MindropApp extends StatelessWidget {
  /// [locale] اختياري: `null` يعني "اتبع لغة الجهاز" (السلوك الطبيعي
  /// للتطبيق). نمرّره صراحةً بالاختبارات، وبيفيدنا لاحقًا لو أضفنا
  /// خيار تبديل لغة يدوي داخل الإعدادات.
  const MindropApp({super.key, this.locale});

  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // اسم العلامة التجارية — لا يُترجم عمدًا.
      title: 'Mindrop',
      debugShowCheckedModeBanner: false,

      // التطبيق داكن دائمًا — الهوية نفسها مبنية على الظلام والتوهج،
      // فما فيه نسخة فاتحة منطقية منها.
      theme: MindropTheme.dark(),
      darkTheme: MindropTheme.dark(),
      themeMode: ThemeMode.dark,

      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // نطابق على رمز اللغة فقط ونتجاهل البلد: جهاز على ar-SA أو ar-EG
      // أو en-GB لازم يلقى واجهته. بدون هذا، Flutter يرفض المطابقة
      // ويسقط على أول لغة بالقائمة.
      localeResolutionCallback: (deviceLocale, supported) {
        if (deviceLocale != null) {
          for (final candidate in supported) {
            if (candidate.languageCode == deviceLocale.languageCode) {
              return candidate;
            }
          }
        }
        // أي لغة غير مدعومة → عربي (السوق الأساسي).
        return const Locale('ar');
      },

      home: const RecordScreen(),
    );
  }
}
