import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// حاوية زجاجية داكنة (Glassmorphism) — العنصر البنائي الأساسي بالهوية.
///
/// تحذير أداء: كل نسخة من هذه الحاوية تنشئ [BackdropFilter]، وهو من
/// أغلى العمليات بـ Flutter لأنه يقرأ ما خلفه ويعيد ضبابيته كل إطار.
/// خلّ عددها بالشاشة الواحدة محدودًا (٣–٤ كحد أقصى)، ولا تستخدمها
/// أبدًا داخل عناصر قائمة طويلة (ListView) — استخدم لونًا شبه شفاف
/// بدون ضبابية هناك.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 24,
    this.opacity = 0.45,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// شفافية طبقة الزجاج (٠.٣ – ٠.٨ حسب وثيقة الهوية).
  final double opacity;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: MindropColors.glass.withValues(alpha: opacity),
            borderRadius: radius,
            border: Border.all(color: MindropColors.glassBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
