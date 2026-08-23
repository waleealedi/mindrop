import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mind_map.dart';
import '../theme/app_theme.dart';

/// يرسم الخريطة الذهنية على كانفس واحد.
///
/// **ملاحظة أداء مقصودة:** ما فيه أي `BackdropFilter`/زجاج هنا، ولا
/// `MaskFilter.blur`. الضبابية الحقيقية تعيد قراءة الطبقة اللي خلفها كل
/// إطار، وكانفس يُعاد رسمه مع كل إصبع على الشاشة هو بالضبط الحالة اللي
/// وُضعت القاعدة لها. حتى "التوهج" هنا مبني من حلقات مصمتة متدرجة الشفافية
/// لا من فلتر ضباب — نفس النتيجة البصرية تقريبًا بتكلفة صفر.
///
/// كل تخطيط النصوص محسوب مسبقًا داخل [LaidOutNode]، فالرسم نفسه ما فيه
/// قياس نص إطلاقًا. الأغصان كذلك محضّرة مسبقًا، ولا يُعاد بناؤها إلا أثناء
/// أنيميشن الدخول وحده — لأن طرفيها يتحركان وقتها فعلًا.
class MindMapPainter extends CustomPainter {
  MindMapPainter({
    required this.layout,
    required this.selectedId,
    required this.entrance,
    required this.selectionT,
  });

  final MindMapLayout layout;
  final String? selectedId;

  /// تقدّم أنيميشن الدخول (0..1). عند 1 يستعمل الرسّام المسارات المحضّرة.
  final double entrance;

  /// تقدّم إبراز التحديد (0..1).
  final double selectionT;

  /// نافذة ظهور العقدة الواحدة داخل زمن الأنيميشن الكلي. أقصر من 1 عشان
  /// العقد تتتابع (stagger) بدل ما تظهر كلها مع بعض.
  static const _window = 0.45;

  bool get _entering => entrance < 1;

  double _progressFor(double start) =>
      ((entrance - start) / _window).clamp(0.0, 1.0);

  /// موضع العقدة الحالي: أثناء الدخول تنطلق من مركز الجذر للخارج، فتقرأ
  /// الحركة كتفرّع من التسجيل لا كظهور عشوائي.
  Offset _centerOf(LaidOutNode n, double eased) =>
      Offset.lerp(layout.rootCenter, n.center, eased)!;

  @override
  void paint(Canvas canvas, Size size) {
    final related = _relatedIds();

    _paintEdges(canvas, related);
    for (final n in layout.nodes) {
      _paintNode(canvas, n, related);
    }
  }

  /// العقدة المحددة + أبوها + أبناؤها. البقية تخفت عند التحديد بدل ما
  /// تبقى بنفس الوزن البصري — التحديد بلا خفوت ما يقرأ كتحديد.
  Set<String>? _relatedIds() {
    final id = selectedId;
    if (id == null) return null;
    final set = <String>{id};
    for (final e in layout.edges) {
      if (e.fromId == id) set.add(e.toId);
      if (e.toId == id) set.add(e.fromId);
    }
    return set;
  }

  double _dimFor(String id, Set<String>? related) {
    if (related == null) return 1;
    return related.contains(id) ? 1.0 : 1.0 - 0.62 * selectionT;
  }

  // ------------------------------------------------------------------ أغصان

  void _paintEdges(Canvas canvas, Set<String>? related) {
    for (final e in layout.edges) {
      final from = layout.nodeById(e.fromId);
      final to = layout.nodeById(e.toId);
      if (from == null || to == null) continue;

      final t = _progressFor(e.entranceStart);
      if (t <= 0) continue;

      final eased = Curves.easeOutCubic.transform(t);
      final highlighted =
          related != null && related.contains(e.fromId) && related.contains(e.toId);
      final dim = math.min(_dimFor(e.fromId, related), _dimFor(e.toId, related));

      final Path path;
      if (_entering) {
        // الطرفان يتحركان أثناء الدخول، فالمسار المحضّر ما ينفع — نبنيه
        // من المواضع الحالية ونقصّه عند نسبة النمو نفسها.
        final a = _centerOf(from, Curves.easeOutCubic.transform(
          _progressFor(from.entranceStart),
        ));
        final b = _centerOf(to, eased);
        final sFrom = 0.32 + 0.68 * Curves.easeOutCubic.transform(
          _progressFor(from.entranceStart),
        );
        path = branchPath(
          a,
          from.radius * sFrom,
          b,
          to.radius * (0.32 + 0.68 * eased),
          t: eased,
        );
      } else {
        path = e.path;
      }

      final alpha = (highlighted ? 0.72 : 0.30) * eased * dim;
      canvas.drawPath(
        path,
        Paint()..color = e.color.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }
  }

  // -------------------------------------------------------------------- عقد

  void _paintNode(Canvas canvas, LaidOutNode n, Set<String>? related) {
    final t = _progressFor(n.entranceStart);
    if (t <= 0) return;

    final eased = Curves.easeOutCubic.transform(t);
    final selected = n.node.id == selectedId;
    final dim = _dimFor(n.node.id, related);

    // نبضة خفيفة عند التحديد: تكبير 8% كافٍ ليُقرأ كاستجابة بدون ما يزيح
    // الجيران أو يكسر الشكل العام.
    final scale = (0.32 + 0.68 * eased) * (selected ? 1 + 0.08 * selectionT : 1);
    final center = _centerOf(n, eased);
    final fade = Curves.easeOut.transform(math.min(1, t * 1.6)) * dim;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    switch (n.level) {
      case MindMapLevel.root:
        _paintRoot(canvas, n, fade, selected);
      case MindMapLevel.category:
        _paintCategory(canvas, n, fade, selected);
      case MindMapLevel.item:
        _paintItem(canvas, n, fade, selected);
    }

    // النص يظهر متأخرًا عن الشكل: نص بمقاس 0.4 يطلع ملطّخًا، فما فيه فايدة
    // من إظهاره قبل ما تقرب العقدة حجمها النهائي.
    final textFade =
        (((t - 0.45) / 0.55).clamp(0.0, 1.0)) * dim;
    if (textFade > 0.01) _paintContent(canvas, n, textFade);

    canvas.restore();
  }

  /// توهج مبني من حلقات مصمتة — بديل `MaskFilter.blur` بتكلفة صفر.
  void _paintHalo(Canvas canvas, Path shape, Color color, double strength) {
    if (strength <= 0.01) return;
    for (var i = 3; i >= 1; i--) {
      final s = 1 + i * 0.13;
      canvas.save();
      canvas.scale(s);
      canvas.drawPath(
        shape,
        Paint()
          ..color = color.withValues(
            alpha: (strength * 0.09 / i).clamp(0.0, 1.0),
          ),
      );
      canvas.restore();
    }
  }

  void _paintRoot(Canvas canvas, LaidOutNode n, double fade, bool selected) {
    _paintHalo(canvas, n.shape, n.color, fade * (selected ? 1.6 : 1.0));

    // تعبئة معتمة أولًا ثم صبغة اللون فوقها.
    //
    // كانت التعبئة لونًا واحدًا بشفافية 0.20، فالأغصان اللي تبدأ **داخل**
    // حدود الجذر تبان من تحته كأشكال زاويّة داكنة تشوّه الكتلة. الطبقة
    // المعتمة تحجبها، والصبغة فوقها تحافظ على التوهج البرتقالي.
    canvas.drawPath(
      n.shape,
      Paint()
        ..color = MindropColors.background
            .withValues(alpha: (0.96 * fade).clamp(0.0, 1.0)),
    );
    canvas.drawPath(
      n.shape,
      Paint()..color = n.color.withValues(alpha: 0.26 * fade),
    );
    canvas.drawPath(
      n.shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = n.color.withValues(alpha: (0.95 * fade).clamp(0.0, 1.0)),
    );
  }

  void _paintCategory(Canvas canvas, LaidOutNode n, double fade, bool selected) {
    if (selected) _paintHalo(canvas, n.shape, n.color, fade * 1.4);

    // نفس سبب الجذر: طبقة معتمة تحجب الأغصان المارّة تحت الكتلة.
    canvas.drawPath(
      n.shape,
      Paint()
        ..color = MindropColors.background
            .withValues(alpha: (0.95 * fade).clamp(0.0, 1.0)),
    );
    canvas.drawPath(
      n.shape,
      Paint()
        ..color = MindropColors.glass
            .withValues(alpha: ((selected ? 0.92 : 0.74) * fade).clamp(0.0, 1.0)),
    );
    canvas.drawPath(
      n.shape,
      Paint()..color = n.color.withValues(alpha: 0.16 * fade),
    );
    canvas.drawPath(
      n.shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.2 : 1.6
        ..color = n.color.withValues(alpha: (0.85 * fade).clamp(0.0, 1.0)),
    );
  }

  void _paintItem(Canvas canvas, LaidOutNode n, double fade, bool selected) {
    if (selected) _paintHalo(canvas, n.shape, n.color, fade * 1.2);

    canvas.drawPath(
      n.shape,
      Paint()
        ..color = MindropColors.glass
            .withValues(alpha: ((selected ? 0.94 : 0.66) * fade).clamp(0.0, 1.0)),
    );
    canvas.drawPath(
      n.shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.8 : 1.0
        ..color = n.color.withValues(
          alpha: ((selected ? 0.95 : 0.42) * fade).clamp(0.0, 1.0),
        ),
    );
  }

  // ------------------------------------------------------------ محتوى العقدة

  /// المحتوى يُرسم بإحداثيات محلية حول (0,0) — نفس فضاء [LaidOutNode.shape].
  void _paintContent(Canvas canvas, LaidOutNode n, double fade) {
    switch (n.level) {
      case MindMapLevel.item:
        // كبسولة: النص وحده، متمركزًا.
        _paintPainter(canvas, n.textPainter,
            Offset(-n.textPainter.width / 2, -n.textPainter.height / 2), fade);

      case MindMapLevel.root:
      case MindMapLevel.category:
        // كتلة: عمود من أيقونة ← نص ← عدّاد (للفئة فقط).
        final icon = n.iconPainter;
        final count = n.countPainter;
        final gap = 4.0;

        var total = n.textPainter.height;
        if (icon != null) total += icon.height + gap;
        if (count != null) total += count.height + gap * 0.5;

        var y = -total / 2;
        if (icon != null) {
          _paintPainter(canvas, icon, Offset(-icon.width / 2, y), fade);
          y += icon.height + gap;
        }
        _paintPainter(canvas, n.textPainter,
            Offset(-n.textPainter.width / 2, y), fade);
        y += n.textPainter.height + gap * 0.5;
        if (count != null) {
          _paintPainter(canvas, count, Offset(-count.width / 2, y), fade * 0.85);
        }
    }
  }

  /// يرسم [TextPainter] بشفافية بدون إعادة تخطيطه.
  ///
  /// `saveLayer` هنا مقصود ومحدود: بديله تعديل `TextPainter.text` كل إطار،
  /// وهذا يستدعي `layout()` من جديد — أغلى بمراحل من طبقة صغيرة بحجم النص.
  /// ونتخطاه كليًا عند الشفافية الكاملة، وهي الحالة الساكنة الغالبة.
  void _paintPainter(
    Canvas canvas,
    TextPainter tp,
    Offset offset,
    double fade,
  ) {
    if (fade >= 0.995) {
      tp.paint(canvas, offset);
      return;
    }
    final rect = Rect.fromLTWH(offset.dx, offset.dy, tp.width, tp.height);
    canvas.saveLayer(
      rect.inflate(2),
      Paint()..color = Colors.white.withValues(alpha: fade.clamp(0.0, 1.0)),
    );
    tp.paint(canvas, offset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MindMapPainter old) =>
      old.layout != layout ||
      old.selectedId != selectedId ||
      old.entrance != entrance ||
      old.selectionT != selectionT;
}
