import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// حوار إعادة تسمية تسجيل.
///
/// ---------------------------------------------------------------------------
/// **ليش ودجت مستقلة ذات حالة، ومو `showDialog` بـ `TextEditingController`
/// محلي داخل دالة الشاشة؟** لأن الثانية انهارت فعلًا على الجهاز.
///
/// `showDialog` يرجّع `Future` يكتمل لحظة `Navigator.pop`، **لا** بعد
/// انتهاء حركة الخروج: `Route.didPop` ينادي `didComplete` فورًا، بينما
/// `finalizeRoute` (اللي يفكّ الشجرة فعلًا) ينتظر الحركة تخلص. فالسطر
/// اللي بعد `await` يشتغل والحوار لسا معلّق على الشاشة وحيّ.
///
/// وقتها كان الكود ينادي `controller.dispose()` مباشرة بعد الـ`await`،
/// فيصير:
///   1. `ChangeNotifier` ينحرّر بينما `EditableText` لسا مشترك فيه.
///   2. تخلص الحركة، فيفكّ الإطار الشجرة وينادي `EditableText.dispose()`
///      اللي ينادي `controller.removeListener(...)` على كائن محرَّر →
///      استثناء **داخل** مسير `deactivate`/`unmount`.
///   3. المسير ينقطع بالنص، فتُترك عناصر `InheritedElement` تابعة للحوار
///      (`Localizations`، `MediaQuery`، `Theme`…) وهي «معطَّلة ولها تابعون».
///   4. تنفجر `assert(_dependents.isEmpty)` بـ `debugDeactivated()`.
///
/// الشاشة الحمراء بالجهاز كانت تعرض الخطوة 4 وحدها — آخر السلسلة — وهذا
/// اللي خلّى العرض يبدو وكأنه مشكلة `InheritedWidget`. الأصل كان الخطوة 1.
///
/// الحل هنا يلغي عدم التطابق من أصله: العمر يملكه `State` داخل نفس الشجرة،
/// فـ`dispose()` يجي بترتيب الإطار الصحيح — الأبناء قبل الآباء، يعني
/// `EditableText.dispose()` (وفيها `removeListener`) **قبل** تحرير المتحكّم.
/// ---------------------------------------------------------------------------
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, this.initialTitle});

  final String? initialTitle;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle ?? '');
  }

  @override
  void dispose() {
    // يجي بعد ما ينفكّ كل الأبناء — وهذا كل الفرق عن النسخة اللي انهارت.
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(t.renameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        // نفس سقف الباك-إند بالضبط، فما يقدر المستخدم يكتب عنوانًا أطول
        // مما يسمح به المخزَّن.
        maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: t.renameHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

/// يفتح [RenameDialog] ويرجّع النص كما كتبه المستخدم، أو `null` لو ألغى.
///
/// القصّ والتحقّق مسؤولية المستدعي عمدًا: الحوار يجمع نصًا، وقرار «فاضي =
/// لا تغيير» قرار الشاشة لا قرار حقل الإدخال.
Future<String?> showRenameDialog(
  BuildContext context, {
  String? initialTitle,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => RenameDialog(initialTitle: initialTitle),
  );
}
