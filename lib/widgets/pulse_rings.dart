import 'package:flutter/material.dart';

/// حلقات متحدة المركز تنبعث من زر التسجيل أثناء التسجيل.
///
/// الغرض منها وظيفي مو زخرفي: الزر نفسه ساكن بمكانه بعد الضغط، فالحلقات
/// هي اللي تخبر المستخدم إن الجهاز "يستقبل" فعلاً — إشارة حياة محيطية
/// يلتقطها بطرف عينه وهو يتكلم، بدون ما يحتاج يركّز على الشاشة.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    required this.child,
    required this.active,
    required this.color,
    this.level = 0,
    this.ringCount = 2,
    this.startRadius = 46,
    this.endRadius = 118,
  });

  final Widget child;
  final bool active;

  /// مستوى الصوت (0..1) — يزيد وضوح الحلقات مع ارتفاع الصوت.
  final double level;

  /// **مطلوب عمدًا.** كان له افتراضي `Color(0xFFFF7A1A)` مكتوب حرفيًا —
  /// وهذا يخالف قاعدة «الألوان من MindropColors فقط»، وكان يمر بصمت لأن
  /// المستدعي الوحيد ما يمرّر لونًا أصلًا. جعله مطلوبًا يمنع تكرارها.
  final Color color;

  /// حلقتان، حسب تصدير Stitch (`inset-0` و`inset-4` بإزاحة نصف ثانية).
  /// كانت أربعًا: الفرق إن الأربع تقرأ كموجة متصلة، والاثنتين كنبضة أوضح.
  final int ringCount;

  /// نصف القطر الذي تولد عنده الحلقة (عادة = نصف قطر الزر).
  final double startRadius;

  /// نصف القطر الذي تتلاشى عنده تمامًا.
  final double endRadius;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  double _smooth = 0;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.active) _clock.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseRings oldWidget) {
    super.didUpdateWidget(oldWidget);

    _smooth = _smooth * 0.75 + widget.level * 0.25;

    if (widget.active && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!widget.active && _clock.isAnimating) {
      // نوقف عند اكتمال الدورة الحالية بدل القطع المفاجئ، عشان الحلقات
      // تكمل تلاشيها للخارج بدل ما تختفي فجأة.
      _clock.animateTo(1, duration: const Duration(milliseconds: 400)).then((_) {
        if (mounted && !widget.active) _clock.stop();
      });
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _clock,
                builder: (context, _) => CustomPaint(
                  painter: _RingsPainter(
                    t: _clock.value,
                    intensity: widget.active
                        ? (0.35 + _smooth.clamp(0.0, 1.0) * 0.65)
                        : 0,
                    color: widget.color,
                    count: widget.ringCount,
                    startRadius: widget.startRadius,
                    endRadius: widget.endRadius,
                  ),
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.t,
    required this.intensity,
    required this.color,
    required this.count,
    required this.startRadius,
    required this.endRadius,
  });

  final double t;
  final double intensity;
  final Color color;
  final int count;
  final double startRadius;
  final double endRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;

    final center = Offset(size.width / 2, size.height / 2);
    final span = endRadius - startRadius;

    for (var i = 0; i < count; i++) {
      // كل حلقة تتقدم بنفس الدورة لكن بإزاحة ثابتة — فتظهر كموجات
      // متتابعة تخرج من الزر بانتظام.
      final p = (t + i / count) % 1.0;
      final radius = startRadius + span * p;

      // تتلاشى كلما ابتعدت، مع ظهور سريع بأول الطريق عشان ما تولد
      // فجأة بحافة الزر.
      final fade = (1 - p) * (p < 0.12 ? p / 0.12 : 1.0);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 - p * 0.7
          ..color = color.withValues(alpha: fade * intensity * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.t != t || old.intensity != intensity;
}
