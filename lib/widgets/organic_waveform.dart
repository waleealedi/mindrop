import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// موجة صوتية عضوية متوهجة — بديل الأعمدة العمودية.
///
/// الفكرة: بدل ما نرسم تاريخ العيّنات كأعمدة، نرسم ٣ "أشرطة" منحنية
/// متداخلة تتموّج باستمرار، ويتحكم مستوى الصوت الحقيقي بسعة تموّجها
/// وسماكتها وشدة توهجها. النتيجة قريبة من موجة Siri: كائن حي واحد
/// يتنفّس، مو مخطط بيانات.
///
/// تقنيًا:
/// - كل شريط شكل مغلق (Path) بين حافتين، مرسوم مرتين: مرة مبلورة
///   (هالة التوهج) ومرة حادة فوقها.
/// - `BlendMode.plus` يجمع ألوان الأشرطة المتداخلة جمعًا ضوئيًا بدل ما
///   يغطي الأعلى الأسفل — وهذا بالضبط اللي يعطي إحساس الضوء لا الطلاء.
/// - غلاف (envelope) على شكل نصف جيب يخلي الموجة سميكة بالوسط ومتلاشية
///   عند الحواف، فما تنقطع بحدة عند طرفي الشاشة.
class OrganicWaveform extends StatefulWidget {
  const OrganicWaveform({
    super.key,
    required this.level,
    this.active = true,
  });

  /// مستوى الصوت الحالي مطبَّعًا بين 0 و1.
  final double level;

  /// عند false تتجمّد الحركة وتخفت — نوقف الأنيميشن فعليًا لتوفير البطارية.
  final bool active;

  @override
  State<OrganicWaveform> createState() => _OrganicWaveformState();
}

class _OrganicWaveformState extends State<OrganicWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  /// مستوى منعَّم: يمنع الموجة ترجف مع كل قراءة مايك.
  double _smooth = 0;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    if (widget.active) _clock.repeat();
  }

  @override
  void didUpdateWidget(covariant OrganicWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);

    _smooth = _smooth * 0.72 + widget.level * 0.28;

    if (widget.active && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!widget.active && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _OrganicWavePainter(
            t: _clock.value,
            level: _smooth.clamp(0.0, 1.0),
            active: widget.active,
          ),
        ),
      ),
    );
  }
}

class _Ribbon {
  const _Ribbon({
    required this.from,
    required this.to,
    required this.freq,
    required this.phase,
    required this.speed,
    required this.amp,
    required this.thickness,
  });

  final Color from;
  final Color to;

  /// عدد الموجات الكاملة عبر عرض الشريط.
  final double freq;
  final double phase;

  /// سرعة الانزلاح الأفقي (سالب = اتجاه معاكس).
  final double speed;

  /// نسبة السعة من أقصى ارتفاع متاح.
  final double amp;

  /// سماكة الشريط كنسبة من الارتفاع.
  final double thickness;
}

class _OrganicWavePainter extends CustomPainter {
  _OrganicWavePainter({
    required this.t,
    required this.level,
    required this.active,
  });

  /// موضع الزمن بالدورة (0..1).
  final double t;
  final double level;
  final bool active;

  /// **ثلاث درجات داخل عائلة القرمزي، لا ثلاثة ألوان مختلفة.**
  ///
  /// الجولة السابقة تركتها فيروزي/أزرق/برتقالي لأن نظام Crimson لهجة واحدة
  /// وما فيه ثلاثية جاهزة تُنسخ. الحل هنا تدرّج داخل العائلة نفسها:
  /// `primary-container` الحيّ، `primary` الفاتح، `inverse-primary` الغامق —
  /// الثلاثة من التصدير، ولا واحد مخترع.
  ///
  /// ما نسخنا معالجة Stitch للموجة: تصديره شريط تقدّم مسطّح بدرجتين، وهذا
  /// كائن عضوي بثلاثة أشرطة متداخلة. الأشكال والحركة كما هي، اللون وحده تغيّر.
  ///
  /// ترددات وسرعات غير متناسبة عمدًا (2.0 / 3.1 / 2.6 و 1.0 / -0.72 / 0.5)
  /// عشان الأشرطة ما ترجع لنفس الوضع بشكل دوري ملحوظ — الحركة تبين
  /// عضوية بدل ما تبين حلقة مكررة.
  static const _ribbons = <_Ribbon>[
    _Ribbon(
      from: MindropColors.crimsonPrimaryContainer,
      to: MindropColors.crimsonPrimary,
      freq: 2.0,
      phase: 0.0,
      speed: 1.0,
      amp: 1.0,
      thickness: 0.085,
    ),
    _Ribbon(
      from: MindropColors.crimsonDeep,
      to: MindropColors.crimsonPrimaryContainer,
      freq: 3.1,
      phase: 1.7,
      speed: -0.72,
      amp: 0.70,
      thickness: 0.060,
    ),
    _Ribbon(
      from: MindropColors.crimsonPrimary,
      to: MindropColors.crimsonDeep,
      freq: 2.6,
      phase: 3.4,
      speed: 0.50,
      amp: 0.46,
      thickness: 0.040,
    ),
  ];

  static const _steps = 80;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final cy = size.height / 2;
    final maxAmp = size.height * 0.40;

    // حد أدنى للحياة: حتى بالصمت تبقى الموجة خيطًا رفيعًا يتنفّس بدل
    // ما تختفي تمامًا وتخلي الشاشة تبين معطلة.
    final l = active ? (0.14 + level * 0.86) : 0.07;

    final rect = Offset.zero & size;

    for (final r in _ribbons) {
      final path = Path();

      double wave(double xn) {
        // غلاف: 0 عند الحواف، 1 بالوسط.
        final env = math.pow(math.sin(math.pi * xn), 1.4).toDouble();
        final a = math.sin(
          xn * 2 * math.pi * r.freq + r.phase + t * 2 * math.pi * r.speed,
        );
        final b = math.sin(
          xn * 2 * math.pi * r.freq * 1.9 -
              r.phase +
              t * 2 * math.pi * r.speed * 1.6,
        );
        return env * (a * 0.65 + b * 0.35) * maxAmp * r.amp * l;
      }

      double half(double xn) {
        final env = math.pow(math.sin(math.pi * xn), 0.75).toDouble();
        return env * size.height * r.thickness * (0.4 + l * 0.6);
      }

      // الحافة العليا: يسار ← يمين
      for (var i = 0; i <= _steps; i++) {
        final xn = i / _steps;
        final x = xn * size.width;
        final y = cy + wave(xn) - half(xn);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      // الحافة السفلى: يمين ← يسار (يقفل الشكل)
      for (var i = _steps; i >= 0; i--) {
        final xn = i / _steps;
        path.lineTo(xn * size.width, cy + wave(xn) + half(xn));
      }
      path.close();

      final shader = LinearGradient(
        colors: [
          r.from.withValues(alpha: 0),
          r.from.withValues(alpha: 0.95),
          r.to.withValues(alpha: 0.95),
          r.to.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.26, 0.74, 1.0],
      ).createShader(rect);

      // هالة: نفس الشكل مبلورًا تحت الشكل الحاد.
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + 14 * l),
      );

      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.plus,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrganicWavePainter old) =>
      old.t != t || old.level != level || old.active != active;
}
