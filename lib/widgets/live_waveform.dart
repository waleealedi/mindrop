import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// موجة أعمدة حيّة مبنية على **قراءات مايك حقيقية** — لا حركة معلَّبة.
///
/// كل عمود هنا عيّنة واحدة فعلية من `Amplitude.current` (dBFS) بعد تطبيعها
/// في [AudioRecorderService.levelStream]. ارتفاع العمود = ما سجّله المايك
/// بتلك اللحظة، وما فيه أي مذبذب أو ساعة أنيميشن تولّد الشكل.
///
/// **هذا هو بيت القصيد، فلا يُعكَس بجولة تجميل لاحقة:** الشكل السابق
/// (`organic_waveform.dart`) كان ثلاثة أشرطة جيبية تتحرك بساعة مدتها ٧ ثوانٍ،
/// ومستوى الصوت يعدّل سعتها وسماكتها فقط. يعني الحركة موجودة حتى بالصمت،
/// والشكل ما يقابل الكلام. المستخدم جرّبه وقال صراحةً إنه يبي سلوك مسجّل
/// النظام: أعمدة تقرأ الصوت لحظة بلحظة. أي رجوع لشكل مولَّد ذاتيًا يلغي
/// المعنى كله، مثل ما ألغته موجة صف السجل المشتقة من التجزئة (انظر CLAUDE.md).
///
/// العيّنات لا تُنعَّم ولا تُحرَّك بعد رسمها: العمود سجلّ لحظة مضت، وتحريكه
/// بعدها يعني تزوير القراءة. الحركة الوحيدة هي دخول عمود جديد كل ٥٠ms.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({
    super.key,
    required this.samples,
    required this.capacity,
    required this.revision,
    this.active = true,
  });

  /// العيّنات المطبَّعة (0..1)، الأقدم أولًا. الشاشة تملك المخزن لأنها هي
  /// اللي تشترك بالدفق — والويدجت هنا رسّام محض بلا حالة.
  final List<double> samples;

  /// أقصى عدد أعمدة تظهر بالنافذة. يحدد عرض العمود لأن العرض المتاح
  /// يُقسَّم عليه، فيبقى الشكل نفسه على أي مقاس شاشة.
  final int capacity;

  /// عدّاد يتغيّر مع كل عيّنة جديدة.
  ///
  /// ضروري لأننا نعدّل القائمة في مكانها بدل ما ننشئ نسخة كل ٥٠ms: هوية
  /// الكائن ما تتغيّر، فلو قارن [CustomPainter.shouldRepaint] القائمة نفسها
  /// ما انرسم شي أبدًا.
  final int revision;

  /// عند false (إيقاف مؤقت) نجمّد التاريخ ونخفته بدل ما نمسحه — العيّنات
  /// اللي انسجلت فعلًا تبقى صحيحة، هي بس مو «الآن».
  final bool active;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LiveWavePainter(
          samples: samples,
          capacity: capacity,
          revision: revision,
          active: active,
          // داخل `CustomPainter` ما فيه `Directionality` محيط إطلاقًا،
          // فنقرأها هنا ونمرّرها صراحةً. تفاصيل ليش تهم بالأسفل.
          direction: Directionality.of(context),
        ),
      ),
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  _LiveWavePainter({
    required this.samples,
    required this.capacity,
    required this.revision,
    required this.active,
    required this.direction,
  });

  final List<double> samples;
  final int capacity;
  final int revision;
  final bool active;
  final TextDirection direction;

  /// نسبة عرض العمود من المسافة المخصصة له — الباقي فراغ.
  static const _barRatio = 0.55;

  /// شفافية أقدم عمود بالنافذة. تلاشٍ خفيف يعطي إحساس «هذا مضى» ويمنع
  /// حدًّا حادًّا عند طرف المخزن قبل ما يمتلئ.
  static const _oldestAlpha = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || samples.isEmpty) return;

    final stride = size.width / capacity;
    final barWidth = stride * _barRatio;
    final radius = Radius.circular(barWidth / 2);

    final cy = size.height / 2;
    // نصف الارتفاع الأقصى، مع هامش يمنع قصّ الحواف المدوّرة.
    final maxHalf = math.max(cy - 2, barWidth / 2);
    // أدنى نصف = نصف عرض العمود، فالصمت يطلع صفًا من النقاط لا فراغًا.
    // شاشة فاضية تمامًا تُقرأ كتطبيق واقف، لا كصمت.
    final minHalf = barWidth / 2;

    final count = math.min(samples.length, capacity);
    final dim = active ? 1.0 : 0.4;

    for (var k = 0; k < count; k++) {
      // k = 0 هو **الأحدث**. نرسم من الأحدث للأقدم عشان يبقى «الآن» مثبّتًا
      // عند طرفه مهما كان المخزن ناقصًا.
      final value = samples[samples.length - 1 - k].clamp(0.0, 1.0);

      // اتجاه الزمن يتبع اتجاه القراءة: بالإنجليزية الزمن يمشي لليمين
      // فالأحدث يمين، وبالعربية يمشي لليسار فالأحدث يسار. الموجة القديمة
      // كانت متماثلة فما كان للاتجاه أثر — أعمدة متحركة ليست كذلك.
      final centerX = direction == TextDirection.rtl
          ? (k + 0.5) * stride
          : size.width - (k + 0.5) * stride;

      final half = minHalf + value * (maxHalf - minHalf);

      // اللون يتبع الارتفاع داخل عائلة القرمزي نفسها (غامق ← حيّ ← فاتح).
      // ترميز مكرر مقصود: الارتفاع وحده يكفي، واللون يزيده وضوحًا بدل ما
      // يحمل معنى مستقلًا — نفس قاعدة «اللون ما هو الإشارة الوحيدة».
      final tone = value < 0.5
          ? Color.lerp(MindropColors.crimsonDeep,
              MindropColors.crimsonPrimaryContainer, value * 2)!
          : Color.lerp(MindropColors.crimsonPrimaryContainer,
              MindropColors.crimsonPrimary, (value - 0.5) * 2)!;

      final age = count == 1 ? 0.0 : k / (count - 1);
      final alpha = (1.0 - age * (1.0 - _oldestAlpha)) * dim;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            centerX - barWidth / 2,
            cy - half,
            centerX + barWidth / 2,
            cy + half,
          ),
          radius,
        ),
        // بلا `MaskFilter.blur`: التوهّج اللي كان بالموجة القديمة كان جزءًا
        // من كونها زينة. مسجّل النظام أعمدة صريحة بلا هالة، وهذا المطلوب.
        Paint()..color = tone.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter old) =>
      old.revision != revision ||
      old.active != active ||
      old.direction != direction ||
      old.capacity != capacity;
}
