import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// أعمدة صغيرة تسبق كل صف بقائمة الأفكار — لغة Stitch لبطاقة التسجيل
/// (`waveform-bar`: عرض 3، أطراف دائرية، ارتفاعات متفاوتة).
///
/// ---------------------------------------------------------------------------
/// **هذي زخرفة، مو قراءة للصوت. الفرق مقصود ومهم.**
///
/// تصدير Stitch نفسه يكتب الارتفاعات يدويًا بكل صف (`h-[30%] h-[80%]` …)، يعني
/// يعاملها كأيقونة تقول «هذا مقطع صوتي» لا كمخطط لمحتواه. اتّبعنا نفس النية:
/// الارتفاعات مشتقّة **حتميًا من معرّف التسجيل**، فنفس التسجيل يعطي نفس الشكل
/// كل مرة، لكنها لا تمثّل الموجة الحقيقية إطلاقًا.
///
/// ليش ما نرسم الموجة الحقيقية: تحتاج فك ترميز ملف الصوت لكل صف داخل قائمة
/// تتمرّر — وهذا بالضبط ما تمنعه قاعدة الأداء بالمشروع. والأهم: موجة تدّعي
/// أنها تمثّل الصوت وهي لا تمثّله كذبة بصرية صغيرة، وهذا تطبيق كل مبدأه ألا
/// يخترع بيانات (راجع مخطط التحليل بلا حقول اختيارية).
///
/// فالتسمية هنا «توقيع» لا «معاينة»، والتعليق يبقى عشان ما يجي أحد لاحقًا
/// ويبني عليها شيئًا يفترض أنها حقيقية.
/// ---------------------------------------------------------------------------
class MiniWaveform extends StatelessWidget {
  const MiniWaveform({
    super.key,
    required this.seed,
    this.muted = false,
    this.barCount = 7,
    this.size = const Size(44, 18),
  });

  /// معرّف التسجيل — مصدر البذرة الحتمية.
  final String seed;

  /// التسجيلات اللي لسا ما اكتملت معالجتها تطلع أخفت.
  final bool muted;

  final int barCount;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: _MiniWavePainter(
          seed: seed.hashCode,
          barCount: barCount,
          muted: muted,
        ),
      ),
    );
  }
}

class _MiniWavePainter extends CustomPainter {
  _MiniWavePainter({
    required this.seed,
    required this.barCount,
    required this.muted,
  });

  final int seed;
  final int barCount;
  final bool muted;

  /// نفس تدرّج الموجة العضوية بشاشة التسجيل: غامق ← حيّ ← فاتح، فالمكانان
  /// يقرآن كعائلة واحدة بدل لونين غير مترابطين.
  static const _ramp = [
    MindropColors.crimsonDeep,
    MindropColors.crimsonPrimaryContainer,
    MindropColors.crimsonPrimary,
  ];

  static Color _rampAt(double t) {
    final scaled = (t.clamp(0.0, 1.0)) * (_ramp.length - 1);
    final i = scaled.floor().clamp(0, _ramp.length - 2);
    return Color.lerp(_ramp[i], _ramp[i + 1], scaled - i)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.0;
    final gap = (size.width - barCount * barW) / (barCount - 1);

    for (var i = 0; i < barCount; i++) {
      // تجزئة حتمية بسيطة: نفس البذرة ونفس الفهرس يعطيان نفس الارتفاع دائمًا.
      final n = math.sin((seed % 1000) * 12.9898 + i * 78.233) * 43758.5453;
      final frac = n - n.floorToDouble();
      final h = size.height * (0.28 + 0.72 * frac);

      final t = barCount == 1 ? 0.5 : i / (barCount - 1);
      final color = _rampAt(t);

      final x = i * (barW + gap);
      final rect = Rect.fromLTWH(x, (size.height - h) / 2, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(barW / 2)),
        Paint()
          ..color = color.withValues(alpha: muted ? 0.32 : 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniWavePainter old) =>
      old.seed != seed || old.muted != muted || old.barCount != barCount;
}
