import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mindrop/l10n/app_localizations.dart';
import 'package:mindrop/widgets/rename_dialog.dart';

// ---------------------------------------------------------------------------
// اختبار انحدار لانهيار إعادة التسمية على الجهاز.
//
// المهم هنا **`pumpAndSettle` بعد الإغلاق**: هو اللي يشغّل حركة خروج الحوار
// للنهاية، وهي بالضبط النافذة اللي كان ينفجر فيها الكود القديم. اختبار
// يتوقف عند `pump()` واحدة كان بيمر وهو مكسور.
//
// النسخة القديمة (متحكّم يُنشأ بدالة الشاشة ويُحرَّر بعد `await showDialog`)
// كانت تسقط هنا بـ «A TextEditingController was used after being disposed»،
// ثم `assert(_dependents.isEmpty)` كأثر جانبي.
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// مضيف صغير: زر يفتح الحوار ويحتفظ بالنتيجة.
  Future<List<String?>> pumpHost(WidgetTester tester, Locale locale) async {
    final results = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await showRenameDialog(context, initialTitle: 'قبل'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    return results;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('الحفظ يرجّع النص ولا يترك أي استثناء بعد حركة الخروج',
      (WidgetTester tester) async {
    final results = await pumpHost(tester, const Locale('ar'));
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'عنوان جديد');
    final t = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;

    await tester.tap(find.text(t.save));
    // الحركة كاملة — هنا كان ينهار القديم.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(results.single, 'عنوان جديد');
  });

  testWidgets('الإلغاء يرجّع null ولا يترك استثناءً',
      (WidgetTester tester) async {
    final results = await pumpHost(tester, const Locale('ar'));
    await openDialog(tester);

    final t = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;
    await tester.tap(find.text(t.cancel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(results.single, isNull);
  });

  testWidgets('فتح وإغلاق مرتين متتاليتين على التوالي — لا استثناء',
      (WidgetTester tester) async {
    final results = await pumpHost(tester, const Locale('ar'));

    for (final title in ['أول', 'ثاني']) {
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), title);
      final t = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;
      await tester.tap(find.text(t.save));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    expect(results, ['أول', 'ثاني']);
  });

  testWidgets('الحوار يفتح بالعنوان الحالي جاهزًا للتحرير',
      (WidgetTester tester) async {
    await pumpHost(tester, const Locale('en'));
    await openDialog(tester);

    expect(find.widgetWithText(TextField, 'قبل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('الإرسال من لوحة المفاتيح يغلق الحوار بلا استثناء',
      (WidgetTester tester) async {
    final results = await pumpHost(tester, const Locale('en'));
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'via keyboard');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(results.single, 'via keyboard');
  });
}
