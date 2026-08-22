import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// خلفية التطبيق: أسود عميق مع "بقع" ضوء متدرجة بالزوايا تعطي إحساس
/// العمق المطلوب بالهوية.
///
/// ملاحظة أداء مقصودة: نستخدم [RadialGradient] بدل `BackdropFilter`
/// أو `ImageFiltered` هنا. النتيجة البصرية شبه متطابقة، لكن التدرج
/// يُرسم على GPU بتكلفة شبه صفرية بينما الضبابية الحقيقية تعيد قراءة
/// كامل الطبقة خلفها كل إطار — وهذا أغلى شي بالشاشة لو تكرر.
/// الضبابية الحقيقية محجوزة للبطاقات الزجاجية فقط (عدد محدود منها).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MindropColors.background,
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -110,
            child: _Glow(color: MindropColors.accent, size: 360, opacity: 0.20),
          ),
          Positioned(
            bottom: -170,
            left: -130,
            child: _Glow(color: MindropColors.neonTeal, size: 400, opacity: 0.13),
          ),
          Positioned(
            top: 240,
            left: -180,
            child: _Glow(color: MindropColors.neonBlue, size: 320, opacity: 0.10),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
