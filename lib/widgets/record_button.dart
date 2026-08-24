import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/audio_recorder_service.dart';
import '../theme/app_theme.dart';

/// زر التسجيل الأساسي: قطرة عضوية متوهجة كبيرة.
///
/// **شكل القطرة من تصدير Stitch** (`record_screen`): أنصاف أقطار غير
/// متساوية لكل زاوية (`border-radius: 40% 60% 70% 30% / 40% 50% 60% 50%`)
/// تعطي كتلة غير منتظمة تقرأ كقطرة لا كزر. تنشدّ لدائرة كاملة عند الضغط
/// (`:active { border-radius: 50% }`) — تفصيلة لمسية رخيصة: الشكل يستجيب
/// للإصبع قبل ما يبدأ التسجيل أصلًا.
///
/// ثلاث سلوكيات مقصودة من وثيقة الهوية، **كلها موجودة من قبل هذا التصدير**:
/// 1) Breathing Animation — بوضع الانتظار يتنفّس الهالة ببطء ليوحي
///    بالجاهزية الفورية بدون ما يشتّت.
/// 2) تفاعل مع الصوت — أثناء التسجيل الهالة تنبض حسب [level] الحقيقي
///    من المايك، فيصير الزر نفسه دليل بصري إن الصوت واصل فعلاً.
/// 3) Haptic Feedback — اهتزاز دقيق عند كل ضغطة، عشان المستخدم يتأكد
///    من بدء/إيقاف التسجيل بدون ما يحتاج ينظر للشاشة.
class RecordButton extends StatefulWidget {
  const RecordButton({
    super.key,
    required this.state,
    required this.onTap,
    this.level = 0,
  });

  final RecorderState state;
  final VoidCallback onTap;

  /// مستوى الصوت الحالي مطبَّعًا بين 0 و1.
  final double level;

  /// أنصاف أقطار القطرة، منسوبة لضلع الزر.
  ///
  /// نفس أرقام Stitch بالترتيب: أفقي (TL TR BR BL) ثم رأسي (TL TR BR BL).
  /// [morph] من 0 (قطرة) إلى 1 (دائرة كاملة).
  static BorderRadius dropletRadius(double side, double morph) {
    Radius r(double hx, double vy) {
      const circle = 0.5;
      return Radius.elliptical(
        side * (hx + (circle - hx) * morph),
        side * (vy + (circle - vy) * morph),
      );
    }

    return BorderRadius.only(
      topLeft: r(0.40, 0.40),
      topRight: r(0.60, 0.50),
      bottomRight: r(0.70, 0.60),
      bottomLeft: r(0.30, 0.50),
    );
  }

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  /// مستوى مُنعَّم: يمنع اهتزاز الهالة العشوائي بين عينة وأخرى.
  double _smoothLevel = 0;

  /// الإصبع على الزر الآن — يشدّ القطرة لدائرة.
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // تنعيم أُسّي بسيط (low-pass) — الهالة تلاحق الصوت بسلاسة
    // بدل ما ترجف مع كل قراءة.
    _smoothLevel = _smoothLevel * 0.6 + widget.level * 0.4;
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.mediumImpact();
    widget.onTap();
  }

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.state == RecorderState.recording;
    final isPaused = widget.state == RecorderState.paused;

    final t = AppLocalizations.of(context)!;

    return Semantics(
      button: true,
      label: isRecording ? t.a11yStopRecording : t.a11yStartRecording,
      child: GestureDetector(
        onTap: _handleTap,
        // الضغط يُلتقط منفصلًا عن النقر عشان الشكل يستجيب أثناء الضغط
        // نفسه، لا بعد رفع الإصبع.
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 150,
          height: 150,
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, _) {
              final breath = Curves.easeInOut.transform(_breath.value);
              final pulse = isRecording ? _smoothLevel.clamp(0.0, 1.0) : breath;

              final haloScale = 1.0 + pulse * (isRecording ? 0.32 : 0.12);
              final haloOpacity =
                  (isRecording ? 0.30 : 0.15) + pulse * 0.18;

              final side = isRecording ? 82.0 : 92.0;
              // الضغط والتسجيل كلاهما يعطي دائرة كاملة.
              final morph = (_pressed || isRecording) ? 1.0 : 0.0;

              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: haloScale,
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            MindropColors.crimsonPrimaryContainer
                                .withValues(alpha: haloOpacity),
                            MindropColors.crimsonPrimaryContainer
                                .withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    width: side,
                    height: side,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // قطرة غير منتظمة بالانتظار، تنشدّ لدائرة كاملة عند
                      // الضغط أو أثناء التسجيل — نفس المكان والمركز بالضبط،
                      // فما يحتاج المستخدم يعيد تحديد مكان الزر عشان يوقف.
                      // الأيقونة (مايك/إيقاف) تبقى الإشارة الأصرح للحالة،
                      // فالشكل يضيف لها ولا يحمل المعنى وحده.
                      borderRadius: RecordButton.dropletRadius(side, morph),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          MindropColors.crimsonPrimaryContainer,
                          MindropColors.crimsonPrimary,
                        ],
                      ),
                      // مقابل `inset 0 0 20px rgba(255,255,255,.1)` عند
                      // Stitch — حافة رفيعة بدل ظل داخلي (Flutter ما يدعمه).
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MindropColors.crimsonPrimaryContainer
                              .withValues(alpha: 0.34 + pulse * 0.22),
                          blurRadius: 30 + pulse * 20,
                          spreadRadius: pulse * 4,
                        ),
                      ],
                    ),
                    child: _StateIcon(
                      isRecording: isRecording,
                      isPaused: isPaused,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// أيقونة حالة الزر، مع عكس الأيقونات ذات الاتجاه بالواجهة العربية.
///
/// **الفجوة اللي تسدّها:** تصدير Crimson ينصّ على عكس كل أيقونة لها معنى
/// اتجاهي (الأسهم وأيقونات التشغيل) بالعربي. فحصنا أيقونات هذا الزر:
///
///   `Icons.arrow_back_rounded`  → `matchTextDirection: true` — ينعكس وحده،
///                                  فلا يحتاج أي شي (بشاشة الخريطة).
///   `Icons.play_arrow_rounded`  → **بلا** الراية، فما ينعكس تلقائيًا.
///   `mic` / `stop`              → بلا اتجاه أصلًا، ما تُعكس.
///
/// فالعكس اليدوي مقصور على «تشغيل» وحدها. الزر نص واجهة لا محتوى مستخدم،
/// فيتبع لغة التطبيق (`Directionality`) لا لغة التسجيل.
class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.isRecording, required this.isPaused});

  final bool isRecording;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      isRecording
          ? Icons.stop_rounded
          : (isPaused ? Icons.play_arrow_rounded : Icons.mic_rounded),
      color: Colors.white,
      size: 34,
    );

    final mirror = isPaused &&
        Directionality.of(context) == TextDirection.rtl;

    return mirror
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scaleByDouble(-1, 1, 1, 1),
            child: icon,
          )
        : icon;
  }
}
