import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mindrop/l10n/app_localizations.dart';
import 'package:mindrop/main.dart';

void main() {
  setUpAll(() {
    // بدون هذا السطر يحاول google_fonts يجلب الخط عبر الشبكة أثناء
    // الاختبار — يبطّئه ويخليه يفشل عشوائيًا حسب الاتصال.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// نمرر اللغة صراحةً بدل الاعتماد على لغة بيئة الاختبار، وإلا صارت
  /// النتيجة تتغيّر حسب إعدادات جهاز المطوّر.
  Future<AppLocalizations> pumpApp(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(MindropApp(locale: locale));
    await tester.pump();
    return AppLocalizations.of(
      tester.element(find.byType(Scaffold)),
    )!;
  }

  testWidgets('الواجهة العربية تفتح بحالة الانتظار الصحيحة باتجاه RTL',
      (WidgetTester tester) async {
    final t = await pumpApp(tester, const Locale('ar'));

    expect(find.text('Mindrop'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);

    expect(find.text(t.hintIdle), findsOneWidget);
    expect(find.text(t.hintRecording), findsNothing);

    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);

    // النص العربي لازم يجي بالنص الفعلي مو بمفتاح الترجمة
    expect(t.hintIdle, 'اضغط وابدأ الكلام');

    final direction =
        Directionality.of(tester.element(find.text(t.hintIdle)));
    expect(direction, TextDirection.rtl);
  });

  testWidgets('الواجهة الإنجليزية تعرض النصوص المترجمة باتجاه LTR',
      (WidgetTester tester) async {
    final t = await pumpApp(tester, const Locale('en'));

    expect(find.text('Mindrop'), findsOneWidget);
    expect(find.text(t.hintIdle), findsOneWidget);
    expect(t.hintIdle, 'Tap and start talking');

    // ما يفترض يظهر أي نص عربي بالواجهة الإنجليزية
    expect(find.text('اضغط وابدأ الكلام'), findsNothing);

    final direction =
        Directionality.of(tester.element(find.text(t.hintIdle)));
    expect(direction, TextDirection.ltr);
  });

  testWidgets('لغة غير مدعومة تسقط على العربية', (WidgetTester tester) async {
    // فرنسي غير مدعوم — المفروض يرجع للعربي حسب localeResolutionCallback
    final t = await pumpApp(tester, const Locale('fr'));
    expect(t.localeName, startsWith('ar'));
    expect(find.text('اضغط وابدأ الكلام'), findsOneWidget);
  });

  test('صيغ الجمع العربية تتصرف صح', () async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    // العربية فيها ست صيغ جمع — لو استُخدمت صيغة `other` لكل الأعداد
    // بيطلع "2 تسجيل" بدل "تسجيلان"، وهذا أول شي يكشف ترجمة كسولة.
    expect(ar.pendingUploads(1), isNot(contains('1 ')));
    expect(ar.pendingUploads(2), isNot(contains('2 ')));
    expect(ar.pendingUploads(7), contains('7'));

    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.pendingUploads(1), '1 waiting to upload');
    expect(en.pendingUploads(5), '5 waiting to upload');
  });
}
