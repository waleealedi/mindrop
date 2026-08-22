import 'package:flutter/material.dart';

import '../models/mind_map.dart';
import '../theme/app_theme.dart';

/// يرسم الخريطة الذهنية على كانفس واحد.
///
/// **ملاحظة أداء مقصودة:** ما فيه أي `BackdropFilter`/زجاج هنا. الضبابية
/// الحقيقية تعيد قراءة الطبقة اللي خلفها كل إطار، وكانفس يُعاد رسمه مع كل
/// إصبع على الشاشة هو بالضبط الحالة اللي وُضعت القاعدة لها. الخلفية هنا
/// ألوان مصمتة بشفافية بسيطة — تكلفتها شبه صفر.
///
/// كل تخطيط النصوص محسوب مسبقًا داخل [LaidOutNode]، فالرسم نفسه ما فيه
/// قياس نص إطلاقًا.
class MindMapPainter extends CustomPainter {
  MindMapPainter({required this.layout, required this.selectedId});

  final MindMapLayout layout;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    _paintEdges(canvas);
    for (final n in layout.nodes) {
      _paintNode(canvas, n, n.node.id == selectedId);
    }
  }

  void _paintEdges(Canvas canvas) {
    for (final e in layout.edges) {
      final from = layout.nodeById(e.fromId);
      final to = layout.nodeById(e.toId);
      if (from == null || to == null) continue;

      final highlighted = selectedId != null &&
          (e.fromId == selectedId || e.toId == selectedId);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 2.2 : 1.3
        ..strokeCap = StrokeCap.round
        ..color = to.color.withValues(alpha: highlighted ? 0.85 : 0.32);

      // منحنى بسيط بدل خط مستقيم: يخلي الفروع تقرأ كأغصان لا كشبكة أسلاك.
      final mid = Offset(
        (from.center.dx + to.center.dx) / 2,
        (from.center.dy + to.center.dy) / 2,
      );
      final path = Path()
        ..moveTo(from.center.dx, from.center.dy)
        ..quadraticBezierTo(
          mid.dx + (to.center.dy - from.center.dy) * 0.12,
          mid.dy - (to.center.dx - from.center.dx) * 0.12,
          to.center.dx,
          to.center.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  void _paintNode(Canvas canvas, LaidOutNode n, bool selected) {
    final isRoot = n.node.kind == MindMapNodeKind.recording;
    final isCategory = n.node.kind == MindMapNodeKind.category;
    final rect = n.rect;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(isRoot ? 18 : 14),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isRoot
            ? n.color.withValues(alpha: 0.22)
            : MindropColors.glass.withValues(alpha: selected ? 0.85 : 0.62),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : (isRoot || isCategory ? 1.4 : 1)
        ..color = n.color.withValues(
          alpha: selected ? 1 : (isRoot || isCategory ? 0.7 : 0.4),
        ),
    );

    // المحتوى (أيقونة + نص) يُتمركز أفقيًا داخل العقدة، فيشتغل مع العربي
    // والإنجليزي بلا فرق.
    final icon = n.iconPainter;
    final iconW = icon == null ? 0.0 : icon.width + 6;
    final contentW = n.textPainter.width + iconW;
    var x = rect.center.dx - contentW / 2;

    if (icon != null) {
      icon.paint(
        canvas,
        Offset(x, rect.center.dy - icon.height / 2),
      );
      x += iconW;
    }

    n.textPainter.paint(
      canvas,
      Offset(x, rect.center.dy - n.textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant MindMapPainter old) =>
      old.layout != layout || old.selectedId != selectedId;
}
