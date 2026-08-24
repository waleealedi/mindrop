import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mind_map.dart';
import '../theme/app_theme.dart';

/// يرسم الخريطة الذهنية على كانفس واحد — بلغة نظام Stitch «Bio-Digital».
///
/// **ملاحظة أداء مقصودة:** ما فيه أي `BackdropFilter`/زجاج هنا، ولا
/// `MaskFilter.blur`. الضبابية الحقيقية تعيد قراءة الطبقة اللي خلفها كل
/// إطار، وكانفس يُعاد رسمه مع كل إصبع على الشاشة هو بالضبط الحالة اللي
/// وُضعت القاعدة لها.
///
/// **انحراف مقصود عن Stitch:** تصديره يحدّد `backdrop-blur-md` على كل عقدة
/// و`blur-xl` على هالة الجذر. أخذنا النتيجة البصرية (سطح شبه شفاف + حد رفيع
/// + توهج) وتركنا الآلية: التعبئة لون مصمت بشفافية، والتوهج حلقات متدرّجة
/// الشفافية بدل فلتر ضباب. القاعدة أقدم من هذا التصدير وسببها قياس حقيقي.
///
/// كل تخطيط النصوص محسوب مسبقًا داخل [LaidOutNode]، فالرسم نفسه ما فيه
/// قياس نص إطلاقًا. الوصلات كذلك محضّرة مسبقًا، ولا يُعاد بناؤها إلا أثناء
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

  /// سماكة الوصلة. Stitch يرسمها `stroke-width="3"` على كانفس عريض؛ 2.6
  /// يعطي نفس الوزن البصري على كانفس جوال.
  static const _edgeWidth = 2.6;

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

  // ----------------------------------------------------------------- وصلات

  void _paintEdges(Canvas canvas, Set<String>? related) {
    for (final e in layout.edges) {
      final from = layout.nodeById(e.fromId);
      final to = layout.nodeById(e.toId);
      if (from == null || to == null) continue;

      final t = _progressFor(e.entranceStart);
      if (t <= 0) continue;

      final eased = Curves.easeOutCubic.transform(t);
      final highlighted = related != null &&
          related.contains(e.fromId) &&
          related.contains(e.toId);
      final dim = math.min(_dimFor(e.fromId, related), _dimFor(e.toId, related));

      final Path path;
      var scale = 1.0;
      if (_entering) {
        // الطرفان يتحركان أثناء الدخول، فالمسار المحضّر ما ينفع — نبنيه
        // من المواضع الحالية ونقصّه عند نسبة النمو نفسها.
        final fromEased =
            Curves.easeOutCubic.transform(_progressFor(from.entranceStart));
        final a = _centerOf(from, fromEased);
        final b = _centerOf(to, eased);
        final sFrom = 0.32 + 0.68 * fromEased;
        final sTo = 0.32 + 0.68 * eased;
        scale = sTo;
        path = branchPath(
          a,
          from.insetAlong(b - a) * sFrom,
          b,
          to.insetAlong(a - b) * sTo,
          t: eased,
        );
      } else {
        path = e.path;
      }

      // شفافية 60% هي قيمة Stitch (`class="opacity-60"`)؛ نرفعها للمسار
      // المحدَّد وننزلها للمخفوت.
      final alpha = (highlighted ? 0.92 : 0.55) * eased * dim;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _edgeWidth * scale
          ..strokeCap = StrokeCap.round
          ..color = e.color.withValues(alpha: alpha.clamp(0.0, 1.0)),
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

    _paintSurface(canvas, n, fade, selected);

    // النص يظهر متأخرًا عن الشكل: نص بمقاس 0.4 يطلع ملطّخًا، فما فيه فايدة
    // من إظهاره قبل ما تقرب العقدة حجمها النهائي.
    final textFade = (((t - 0.45) / 0.55).clamp(0.0, 1.0)) * dim;
    if (textFade > 0.01) _paintContent(canvas, n, textFade);

    canvas.restore();
  }

  /// خلفية العقدة وحدّها.
  ///
  /// القيم من تصدير Stitch: تعبئة `surface-container`، حد بلون الفرع عند
  /// نسبة منخفضة للعناصر، وحد **أبيض 10%** للجذر (`border-white/10`) —
  /// الجذر وحده يعتمد على التوهج النيلي لا على لون حدّه.
  void _paintSurface(Canvas canvas, LaidOutNode n, double fade, bool selected) {
    final isRoot = n.level == MindMapLevel.root;
    final isCategory = n.level == MindMapLevel.category;

    if (isRoot) {
      _paintHalo(canvas, n.shape, n.color, fade * (selected ? 2.6 : 1.9));
    } else if (selected) {
      _paintHalo(canvas, n.shape, n.color, fade * 1.3);
    }

    // طبقة معتمة أولًا: الوصلات تمر تحت الكبسولات، ولولاها بانت من خلفها.
    canvas.drawPath(
      n.shape,
      Paint()
        ..color = MindropColors.background
            .withValues(alpha: (0.94 * fade).clamp(0.0, 1.0)),
    );
    canvas.drawPath(
      n.shape,
      Paint()
        ..color = MindropColors.stitchSurfaceContainer.withValues(
          alpha: ((selected ? 0.98 : 0.86) * fade).clamp(0.0, 1.0),
        ),
    );

    final Color borderColor;
    final double borderAlpha;
    if (isRoot) {
      borderColor = Colors.white;
      borderAlpha = selected ? 0.34 : 0.16;
    } else {
      borderColor = n.color;
      borderAlpha = selected ? 1.0 : (isCategory ? 0.62 : 0.34);
    }

    canvas.drawPath(
      n.shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCategory ? 1.5 : (isRoot ? 1.5 : 1.1)
        ..color =
            borderColor.withValues(alpha: (borderAlpha * fade).clamp(0.0, 1.0)),
    );
  }

  /// توهج مبني من حلقات مصمتة — بديل `blur` بتكلفة صفر.
  void _paintHalo(Canvas canvas, Path shape, Color color, double strength) {
    if (strength <= 0.01) return;
    for (var i = 3; i >= 1; i--) {
      final s = 1 + i * 0.12;
      canvas.save();
      canvas.scale(s);
      canvas.drawPath(
        shape,
        Paint()
          ..color = color.withValues(
            alpha: (strength * 0.085 / i).clamp(0.0, 1.0),
          ),
      );
      canvas.restore();
    }
  }

  // ------------------------------------------------------------ محتوى العقدة

  /// المحتوى يُرسم بإحداثيات محلية حول (0,0) — نفس فضاء [LaidOutNode.shape].
  ///
  /// كل المستويات صف أفقي واحد، بنفس ترتيب المقاسات المحجوزة وقت التخطيط:
  ///   الجذر  : أيقونة + نص
  ///   الفئة  : أيقونة + نص + عدّاد
  ///   العنصر : نقطة + نص
  void _paintContent(Canvas canvas, LaidOutNode n, double fade) {
    final icon = n.iconPainter;
    final count = n.countPainter;
    final text = n.textPainter;

    final iconW = icon == null ? 0.0 : icon.width + kNodeGlyphGap;
    final countW = count == null ? 0.0 : count.width + kNodeGlyphGap;
    final dotW = n.showDot ? kNodeDotSize + kNodeDotGap : 0.0;

    final contentW = iconW + dotW + text.width + countW;
    var x = -contentW / 2;

    void paintLeadingGlyph() {
      if (icon != null) {
        _paintPainter(canvas, icon, Offset(x, -icon.height / 2), fade);
        x += iconW;
      }
      if (n.showDot) {
        final cx = x + kNodeDotSize / 2;
        // هالة صغيرة حول النقطة — مقابل `shadow-[0_0_10px_rgba(...,0.6)]`
        // عند Stitch، بحلقة مصمتة بدل ظل مضبّب.
        canvas.drawCircle(
          Offset(cx, 0),
          kNodeDotSize / 2 + 2.5,
          Paint()..color = n.color.withValues(alpha: 0.22 * fade),
        );
        canvas.drawCircle(
          Offset(cx, 0),
          kNodeDotSize / 2,
          Paint()..color = n.color.withValues(alpha: fade.clamp(0.0, 1.0)),
        );
        x += dotW;
      }
    }

    // الرمز المتصدّر (أيقونة أو نقطة) يسبق النص، و"يسبق" بالعربي = يمين.
    // فنقلب ترتيب الصف كاملًا للعقد العربية بدل ما نترك النقطة بجهة نهاية
    // القراءة — نفس منطق [TranscriptText]، مطبَّقًا على تخطيط لا على نص.
    if (!n.isRtl) {
      paintLeadingGlyph();
      _paintPainter(canvas, text, Offset(x, -text.height / 2), fade);
      x += text.width;
      if (count != null) {
        x += kNodeGlyphGap;
        _paintPainter(canvas, count, Offset(x, -count.height / 2), fade * 0.9);
      }
    } else {
      if (count != null) {
        _paintPainter(canvas, count, Offset(x, -count.height / 2), fade * 0.9);
        x += count.width + kNodeGlyphGap;
      }
      _paintPainter(canvas, text, Offset(x, -text.height / 2), fade);
      x += text.width;
      paintLeadingGlyph();
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
