import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/audio_recorder_service.dart';
import '../theme/app_theme.dart';

/// زر التسجيل الأساسي: دائرة برتقالية متوهجة كبيرة.
///
/// ثلاث سلوكيات مقصودة من وثيقة الهوية:
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

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  /// مستوى مُنعَّم: يمنع اهتزاز الهالة العشوائي بين عينة وأخرى.
  double _smoothLevel = 0;

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
                            MindropColors.accent.withValues(alpha: haloOpacity),
                            MindropColors.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    width: isRecording ? 82 : 92,
                    height: isRecording ? 82 : 92,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // دائرة بوضع الانتظار، تتحول لمربع مدوّر عند
                      // التسجيل — نفس المكان بالضبط، فما يحتاج المستخدم
                      // يعيد تحديد مكان الزر بعينه عشان يوقف.
                      borderRadius:
                          BorderRadius.circular(isRecording ? 26 : 46),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          MindropColors.accentSoft,
                          MindropColors.accent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MindropColors.accent
                              .withValues(alpha: 0.40 + pulse * 0.22),
                          blurRadius: 26 + pulse * 20,
                          spreadRadius: pulse * 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      isRecording
                          ? Icons.stop_rounded
                          : (isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.mic_rounded),
                      color: Colors.white,
                      size: 34,
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
