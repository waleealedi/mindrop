import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'transcript_text.dart';

/// إجراء واحد بورقة الإجراءات.
class RecordingAction {
  const RecordingAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  /// يفصله عن البقية بصريًا: نبرة حمراء وفاصل ومسافة فوقه.
  final bool destructive;
}

/// ورقة إجراءات التسجيل — الضغط المطوّل على صف بقائمة الأفكار.
///
/// ---------------------------------------------------------------------------
/// **`showGeneralDialog` لا `showModalBottomSheet`، وهذا هو السبب الوحيد:**
/// `showModalBottomSheet` ما يعطينا تحكّمًا بالحاجب (barrier) نفسه — يقبل
/// لونًا وبس. الحاجب المضبَّب يحتاج `BackdropFilter` يغطي الشاشة كاملة خلف
/// الورقة، وهذي طبقة داخل المسار لا لون. `showGeneralDialog` يسلّمنا
/// `pageBuilder` كامل الشاشة، فنبني الطبقتين بأنفسنا.
///
/// ---------------------------------------------------------------------------
/// **الضباب هنا استثناء مقصود من قاعدة «لا BackdropFilter» — ومحدود.**
/// القاعدة بالمستودع تمنع الضباب داخل قائمة تتمرّر أو فوق سطح يعيد الرسم كل
/// إطار. هذي الحالة ليست كذلك: الورقة مشروط ظهورها بتوقّف التمرير، وما
/// خلفها ساكن طول ما هي مفتوحة، والطبقة واحدة ومؤقتة تختفي مع الإغلاق —
/// نفس الاستثناء اللي تاخذه دوك شاشة التسجيل بالضبط. القائمة نفسها تبقى
/// بلا أي ضباب كما هي.
/// ---------------------------------------------------------------------------
Future<void> showRecordingActionsSheet(
  BuildContext context, {
  required String? headline,
  required List<RecordingAction> actions,
  required String semanticLabel,
}) {
  return showGeneralDialog<void>(
    context: context,
    // الحاجب الحقيقي طبقتنا المضبَّبة بالأسفل، فما نبي حاجبًا ملوّنًا فوقها.
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    barrierLabel: semanticLabel,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _ActionsSheet(
      headline: headline,
      actions: actions,
      semanticLabel: semanticLabel,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      // تلاشٍ + تكبير طفيف + انزلاق قصير من الأسفل. ثلاثتها من نفس
      // `animation` اللي يوفّرها المسار — ما فيه `AnimationController`
      // جديد ولا `Ticker` إضافي.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            // التكبير من الأسفل: الورقة ملتصقة بالحافة، فالتكبير من
            // مركزها يخليها تنفصل عنها للحظة.
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      );
    },
  );
}

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({
    required this.headline,
    required this.actions,
    required this.semanticLabel,
  });

  final String? headline;
  final List<RecordingAction> actions;
  final String semanticLabel;

  /// نفس نصف قطر `dialogTheme` بالثيم — الورقة من عائلة الحوارات، وهي
  /// القيمة الوحيدة المعرَّفة على مستوى الثيم أصلًا (البقية أرقام موضعية).
  static const _radius = 16.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // الطبقة الأولى: ضباب يغطي الشاشة، وهو نفسه منطقة «اضغط للإغلاق».
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                // تعتيم خفيف فوق الضباب: الضباب وحده يخلي النص خلفه غير
                // مقروء لكنه ما يخفض السطوع، فتبقى الورقة تنافس خلفيتها.
                color: MindropColors.background.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Semantics(
            container: true,
            label: semanticLabel,
            child: Material(
              color: MindropColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(_radius)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    // مقبض بصري يقول «هذي ورقة» — بلا نص، فما يحتاج ترجمة.
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            MindropColors.crimsonOutline.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (headline != null) _buildHeadline(headline!),
                    const SizedBox(height: 6),
                    for (final a in actions) ...[
                      if (a.destructive) _buildSeparator(),
                      _ActionRow(action: a),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// سطر يقول **أي** تسجيل نتعامل معه — سؤال حقيقي بقائمة صفوفها متشابهة.
  /// النص معاد استخدامه من الصف نفسه، ما نجيب شيئًا جديدًا.
  Widget _buildHeadline(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 16, 22, 4),
      child: SizedBox(
        width: double.infinity,
        // محتوى مستخدم: اتجاهه من حروفه هو لا من لغة الواجهة.
        child: TranscriptText(
          text,
          maxLines: 1,
          style: MindropFonts.style(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: MindropColors.crimsonOnSurface,
          ),
        ),
      ),
    );
  }

  /// فاصل قبل الفعل المدمّر وحده. الحذف ما له تراجع، فما يجاور البقية.
  Widget _buildSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      child: Divider(
        height: 1,
        thickness: 1,
        color: MindropColors.crimsonOutline.withValues(alpha: 0.18),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final RecordingAction action;

  @override
  Widget build(BuildContext context) {
    // الحذف بنبرة الخطأ، والبقية بلهجة الهوية. النبرة الفاتحة للأيقونة
    // نفسها (آمنة للنص/الأيقونات على الأسود) والحيّة لخلفية الرقاقة بشفافية
    // 0.14 — **نفس اتفاقية رقاقة الحالة بصف القائمة حرفيًا**، فما فيه درجة
    // جديدة ولا رقم شفافية جديد.
    final iconTint = action.destructive
        ? MindropColors.errorRed
        : MindropColors.crimsonPrimary;
    final chipTint = action.destructive
        ? MindropColors.errorRed
        : MindropColors.crimsonPrimaryContainer;

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        action.onSelected();
      },
      child: Padding(
        // أسخى من كثافة `ListTile` الافتراضية: ارتفاع الصف ~64 بدل ~56،
        // والورقة قصيرة أصلًا فما نخسر شيئًا مقابل هدف لمس أوسع.
        padding: const EdgeInsetsDirectional.fromSTEB(22, 12, 22, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chipTint.withValues(alpha: 0.14),
              ),
              child: Icon(action.icon, size: 20, color: iconTint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                action.label,
                style: MindropFonts.style(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: action.destructive
                      ? MindropColors.errorRed
                      : MindropColors.crimsonOnSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
