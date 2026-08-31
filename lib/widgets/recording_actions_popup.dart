import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// إجراء واحد بمنبثقة الإجراءات.
class RecordingAction {
  const RecordingAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  final IconData icon;

  /// نص الوصف — ما يظهر مكتوبًا، لكنه **مطلوب**: هو التلميح عند الضغط
  /// المطوّل وتسمية قارئ الشاشة معًا. أيقونة بلا اسم ما تُقرأ إطلاقًا.
  final String label;

  final VoidCallback onSelected;

  /// يفصله بنبرته الحمراء — الوحيد بلا تراجع.
  final bool destructive;
}

/// منبثقة إجراءات التسجيل: كبسولة صغيرة تطلع **عند إصبع المستخدم**.
///
/// ---------------------------------------------------------------------------
/// **بديل ورقة سفلية كاملة العرض، لا إضافة فوقها.** الورقة كانت تشتغل صح
/// لكنها تعامل فعلًا موضعيًا (إجراء على صف بعينه) معاملة حدث على مستوى
/// الشاشة: تجي من الحافة، تغطي العرض كله، وتبعد نظر المستخدم عن الصف اللي
/// ضغطه. الكبسولة تبقى عند نقطة اللمس، فالعلاقة بين الصف والإجراء تبقى
/// مرئية بلا ما نكتبها بنص.
///
/// **وسقط معها استثناء الضباب.** الورقة كانت تاخذ `BackdropFilter` يغطي
/// الشاشة كاملة، وكان استثناءً موثّقًا من قاعدة «لا ضباب». المنبثقة ما
/// تحتاجه: هي صغيرة وبجانب الإصبع أصلًا، والحاجب هنا شفاف تمامًا ووظيفته
/// التقاط الضغط للإغلاق وبس. فرجعت القاعدة بلا استثناء.
/// ---------------------------------------------------------------------------
Future<void> showRecordingActionsPopup(
  BuildContext context, {
  required Offset anchor,
  required List<RecordingAction> actions,
  required String semanticLabel,
}) {
  return showGeneralDialog<void>(
    context: context,
    // شفاف: الحاجب موجود لالتقاط الضغط بالخارج فقط، ما نعتّم الشاشة.
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: semanticLabel,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) => _ActionsPopup(
      anchor: anchor,
      actions: actions,
      semanticLabel: semanticLabel,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      // تلاشٍ + تكبير طفيف، الاثنان من حركة المسار نفسها — بلا
      // `AnimationController` ولا `Ticker` إضافي.
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ActionsPopup extends StatelessWidget {
  const _ActionsPopup({
    required this.anchor,
    required this.actions,
    required this.semanticLabel,
  });

  final Offset anchor;
  final List<RecordingAction> actions;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Stack(
      children: [
        // الضغط خارج الكبسولة يغلق. شفاف تمامًا — بلا تعتيم وبلا ضباب.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
          ),
        ),
        CustomSingleChildLayout(
          // المندوب يستلم مقاس الكبسولة **بعد قياسها**، فما نكتب عرضًا ولا
          // ارتفاعًا بأرقام ثابتة: عدد الأزرار أو حجم الخط لو تغيّر، يبقى
          // القلب والقصّ صحيحين بلا تعديل.
          delegate: _PopupLayout(
            anchor: anchor,
            padding: media.padding,
            // هامش أدنى عن حواف الشاشة.
            margin: 12,
          ),
          child: Semantics(
            container: true,
            label: semanticLabel,
            child: Material(
              color: MindropColors.surface,
              // كبسولة: نصف القطر = نصف الارتفاع، فالطرفان نصف دائرة تامة.
              // `StadiumBorder` يحسبها بنفسه فما نربطها برقم ارتفاع.
              shape: StadiumBorder(
                side: BorderSide(color: MindropColors.glassBorder),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 8,
              shadowColor: MindropColors.background,
              child: Padding(
                // متماثل الجانبين، فما فيه ما يُعكس بـ RTL.
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  // `Row` يعكس ترتيب أبنائه تلقائيًا مع RTL، وهذا المطلوب:
                  // «إعادة تسمية» أول ما تقرأ بالعربي كما هي أول ما تقرأ
                  // بالإنجليزي.
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _ActionChip(action: actions[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// يضع الكبسولة عند نقطة اللمس، ويقلبها ويقصّها عند الحواف.
class _PopupLayout extends SingleChildLayoutDelegate {
  const _PopupLayout({
    required this.anchor,
    required this.padding,
    required this.margin,
  });

  /// نقطة الضغط المطوّل بإحداثيات الشاشة.
  final Offset anchor;

  /// حواف النظام (شق الكاميرا، شريط الإيماءات) — نحترمها لا حواف الشاشة
  /// الخام، وإلا طلعت الكبسولة تحت شريط الإيماءات بأجهزة الحافة الكاملة.
  final EdgeInsets padding;

  final double margin;

  /// الطفل يقيس نفسه؛ ما نفرض عليه مقاسًا.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // مسافة بين الإصبع والكبسولة: الإصبع نفسه يغطي ما تحته، فلو لصقناها
    // بالنقطة صارت مخفية تحت اليد.
    const gap = 14.0;

    final minTop = padding.top + margin;
    final maxTop = size.height - padding.bottom - margin - childSize.height;

    // الأصل فوق الإصبع — هناك اليد ما تحجبها.
    var top = anchor.dy - childSize.height - gap;
    // ما فيها مكان فوق؟ نقلبها تحته.
    if (top < minTop) top = anchor.dy + gap;
    // ولو ضاقت الجهتان (شاشة قصيرة، أو ضغطة بأسفل الشاشة تمامًا) نقصّها
    // داخل المتاح بدل ما تختفي. `math.max` يحمي من نطاق مقلوب لو كان
    // الطفل أطول من الشاشة أصلًا.
    top = top.clamp(minTop, math.max(minTop, maxTop));

    // أفقيًا: نتوسّط الإصبع ثم نقصّ على الحافتين.
    //
    // **ما فيه فرق RTL هنا وهذا مقصود لا سهو:** التوسيط والقصّ عمليتان
    // متماثلتان حول نقطة، فتعطيان نفس النتيجة بأي اتجاه. الاتجاه يظهر
    // بترتيب الأيقونات داخل `Row`، وهذا يتكفّل به الإطار.
    final minLeft = margin;
    final maxLeft = size.width - margin - childSize.width;
    var left = anchor.dx - childSize.width / 2;
    left = left.clamp(minLeft, math.max(minLeft, maxLeft));

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PopupLayout old) =>
      old.anchor != anchor || old.padding != padding || old.margin != margin;
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action});

  final RecordingAction action;

  @override
  Widget build(BuildContext context) {
    // **نفس معالجة الرقاقة الملوّنة المبنية سابقًا، بلا اشتقاق جديد:**
    // خلفية دائرية باللون الحيّ بشفافية 0.14 — نفس رقم رقاقة الحالة بصف
    // القائمة — والأيقونة بالدرجة الفاتحة الآمنة للأيقونات على الأسود.
    // الحذف ياخذ `errorRed` للاثنين.
    final iconTint = action.destructive
        ? MindropColors.errorRed
        : MindropColors.crimsonPrimary;
    final chipTint = action.destructive
        ? MindropColors.errorRed
        : MindropColors.crimsonPrimaryContainer;

    return IconButton(
      onPressed: () {
        Navigator.pop(context);
        action.onSelected();
      },
      icon: Icon(action.icon, size: 20),
      // `tooltip` يغذّي التلميح **وتسمية قارئ الشاشة** معًا — لازم لأن
      // الزر بلا نص ظاهر. الضغط المطوّل عليه يعرض الاسم.
      tooltip: action.label,
      style: IconButton.styleFrom(
        foregroundColor: iconTint,
        backgroundColor: chipTint.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        fixedSize: const Size(44, 44),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
