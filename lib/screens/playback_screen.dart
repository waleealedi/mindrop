import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
// `show DateFormat` مقصود: حزمة intl تصدّر صنف `TextDirection` خاص فيها
// يحجب `TextDirection` تبع Flutter لو استوردناها كاملة.
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/app_localizations.dart';
import '../models/recording_draft.dart';
import '../services/firestore_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../widgets/transcript_text.dart';
import 'mind_map_screen.dart';

/// شاشة الاستماع لتسجيل واحد: موجة صوتية حقيقية مستخرجة من الملف نفسه
/// (مو محاكاة)، مع تشغيل/إيقاف وتنقّل بالسحب أو الضغط على الموجة.
///
/// الفرق عن موجة شاشة التسجيل: هذي **تمثيل دقيق** لمحتوى الملف كامل —
/// وظيفتها الملاحة داخل التسجيل، فلازم كل عمود فيها يقابل لحظة حقيقية.
/// موجة شاشة التسجيل بالمقابل تعبيرية بحتة: تؤكد إن الصوت واصل الحين.
class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({
    super.key,
    required this.draft,
    this.transcript,
    this.analysis,
  });

  final RecordingDraft draft;

  /// النص المفرَّغ القادم من الباك-إند عبر Firestore. `null` يعني ما وصل
  /// بعد (أو رُفض بحارس الهلوسة) — الاستماع نفسه يشتغل بدونه طبيعي.
  final String? transcript;

  /// المحتوى المنظّم المستخرَج من النص. `null` يعني التحليل لسا ما خلص.
  final RecordingAnalysis? analysis;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  /// هوامش ثابتة نحسب منها عرض الموجة قبل ما ترسم.
  ///
  /// [WaveformType.fitWidth] يطلب عدد عيّنات مضبوط على العرض الفعلي، وإلا
  /// انقصّ طرف الموجة. نحسبها من عرض الشاشة ناقص الهوامش بدل `LayoutBuilder`
  /// عشان نعرف الرقم قبل استدعاء `preparePlayer` مرة وحدة فقط.
  static const _screenPadding = 20.0;
  static const _cardPadding = 16.0;
  static const _waveHeight = 130.0;

  final _waveStyle = PlayerWaveStyle(
    // الجزء المُشغَّل بالقرمزي الحيّ، والباقي بمحايد Crimson باهت — نفس
    // منطق "أين وصلت" بمسجّلات النظام.
    liveWaveColor: MindropColors.crimsonPrimaryContainer,
    fixedWaveColor: MindropColors.crimsonOutline.withValues(alpha: 0.32),
    // خط الموضع بالدرجة الفاتحة لا بنفس درجة الأعمدة المُشغَّلة: لو أخذ
    // `crimsonPrimaryContainer` نفسه لذاب فيها واختفى مؤشر «وين أنا».
    seekLineColor: MindropColors.crimsonPrimary,
    seekLineThickness: 2,
    // شرط الحزمة: waveThickness لازم يكون أصغر من spacing.
    waveThickness: 3,
    spacing: 6,
    waveCap: StrokeCap.round,
    // القيمة الافتراضية (100) تطلع الموجة شبه مسطّحة مع كلام الجوال:
    // ارتفاع كل عمود = العيّنة × scaleFactor، وقمم الكلام العادي تجي
    // حوالي 0.2، يعني ~20px داخل نصف ارتفاع 65px. 260 تملأ الصندوق.
    scaleFactor: 260,
  );

  late final PlayerController _controller;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int>? _durationSub;
  StreamSubscription<void>? _completionSub;

  bool _preparing = true;
  bool _loadFailed = false;
  int _positionMs = 0;
  int _totalMs = 0;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController();

    _stateSub = _controller.onPlayerStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _durationSub = _controller.onCurrentDurationChanged.listen((ms) {
      if (mounted) setState(() => _positionMs = ms);
    });
    _completionSub = _controller.onCompletion.listen((_) async {
      // نرجّع المؤشر للبداية عشان الضغطة الجاية تعيد التشغيل من أوله
      // بدل ما تعلق بالنهاية.
      await _controller.seekTo(0);
      if (mounted) setState(() => _positionMs = 0);
    });

    // بعد أول إطار: MediaQuery صار جاهزًا فنقدر نحسب عرض الموجة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _completionSub?.cancel();
    // معلوم ومقصود: هذا الاستدعاء يطبع
    // `PlatformException: codec is released already`
    // بالسجل عند الخروج من الشاشة. السبب داخل الحزمة نفسها (2.0.2):
    // `PlayerController.dispose()` ينادي `release()` ثم
    // `stopWaveformExtraction()`، والأخير يصل لـ `WaveformExtractor.stop()`
    // بـ Kotlin اللي ينادي `decoder.stop()` بدون فحص إذا الـ codec
    // انحرر أصلًا. ما نقدر نمسكه هنا لأن `dispose()` معرّف
    // `void dispose() async` — الاستثناء يهرب كخطأ async غير ملتقط.
    // أثره ضجيج بالسجل فقط: التطبيق ما ينهار والموارد تتحرر فعلًا.
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- منطق

  double get _waveWidth =>
      MediaQuery.sizeOf(context).width - (_screenPadding + _cardPadding) * 2;

  Future<void> _prepare() async {
    if (!mounted) return;
    final path = widget.draft.filePath;

    try {
      // الفهرس قد يشير لملف انحذف من برّا التطبيق (منظّف تخزين مثلاً).
      // نفحص وجوده صراحةً بدل ما ننتظر خطأ غامض من الطبقة الأصلية.
      if (!await File(path).exists()) {
        throw FileSystemException('recording file is missing', path);
      }

      await _controller.preparePlayer(
        path: path,
        noOfSamples: _waveStyle.getSamplesForWidth(_waveWidth),
      );
      // pause بدل stop: يحتفظ بالموارد بعد نهاية التشغيل فيقدر المستخدم
      // يعيد الاستماع بدون إعادة تحضير كاملة للملف.
      await _controller.setFinishMode(finishMode: FinishMode.pause);

      if (!mounted) return;
      setState(() {
        _preparing = false;
        // maxDuration من المشغّل أدق، ومدّة المسودة احتياط لو رجع -1.
        _totalMs = _controller.maxDuration > 0
            ? _controller.maxDuration
            : widget.draft.durationMs;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_preparing || _loadFailed) return;

    try {
      if (_controller.playerState.isPlaying) {
        await _controller.pausePlayer();
      } else {
        await _controller.startPlayer();
      }
    } catch (_) {
      // startPlayer يرمي نصًا خامًا (مو Exception) لو فشل التشغيل.
      if (mounted) setState(() => _loadFailed = true);
      return;
    }

    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // --------------------------------------------------------------- بناء

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: MindropColors.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCard(t),
                      _buildTranscript(t),
                      _buildAnalysis(t),
                    ],
                  ),
                ),
              ),
              _buildDock(t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final localeName = Localizations.localeOf(context).toString();
    final createdAt = widget.draft.createdAt;
    final date = DateFormat.yMMMd(localeName).format(createdAt);
    final time = DateFormat.jm(localeName).format(createdAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 20, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: MindropColors.textPrimary,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              // فاصل محايد اتجاهيًا: يشتغل بالعربي والإنجليزي بدون علامة
              // ترقيم خاصة بلغة وحدة.
              '$date · $time',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: MindropColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
      child: GlassContainer(
        borderRadius: 28,
        opacity: 0.42,
        blur: 20,
        padding: const EdgeInsets.symmetric(
          horizontal: _cardPadding,
          vertical: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _waveHeight,
              child: Center(child: _buildWaveArea(t)),
            ),
            const SizedBox(height: 18),
            _buildTimes(),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveArea(AppLocalizations t) {
    if (_loadFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          t.playbackLoadError,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: MindropColors.textSecondary,
          ),
        ),
      );
    }

    // قبل ما يجهز الاستخراج نترك الفراغ فاضيًا بنفس الارتفاع — أي مؤشر
    // تحميل هنا يومض جزء من الثانية ويشوّش أكثر ما يفيد.
    if (_preparing) return const SizedBox.shrink();

    // الرسّام ما يقصّ الأعمدة عند حدود الصندوق: تسجيل عالي جدًا ممكن
    // يتجاوز الارتفاع ويطلع فوق سطر الوقت. ClipRect يحصره داخل حدوده.
    return ClipRect(
      child: AudioFileWaveforms(
        size: Size(_waveWidth, _waveHeight),
        playerController: _controller,
        waveformType: WaveformType.fitWidth,
        playerWaveStyle: _waveStyle,
        // fitWidth يدعم التنقّل بالضغط والسحب معًا.
        enableSeekGesture: true,
        animationCurve: Curves.easeOut,
      ),
    );
  }

  /// النص الكامل بلا قصّ — الشاشة كلها قابلة للتمرير، فطول التفريغ ما
  /// يزاحم شي. هنا `GlassContainer` مسموحة: شاشة ثابتة وحدة مو قائمة.
  Widget _buildTranscript(AppLocalizations t) {
    final transcript = widget.transcript?.trim();
    final hasText = transcript != null && transcript.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_screenPadding, 14, _screenPadding, 0),
      child: GlassContainer(
        borderRadius: 24,
        opacity: 0.34,
        blur: 18,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasText ? Icons.notes_rounded : Icons.hourglass_empty_rounded,
              size: 18,
              color: hasText
                  ? MindropColors.crimsonPrimary
                  : MindropColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              // النص المفرَّغ وحده يتبع اتجاه محتواه؛ رسالة الانتظار نص
              // واجهة عادي فتتبع لغة التطبيق مثل بقية الشاشة.
              child: hasText
                  ? TranscriptText(
                      transcript,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                        color: MindropColors.textPrimary,
                      ),
                    )
                  : Text(
                      t.transcriptPending,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                        color: MindropColors.textSecondary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// المحتوى المنظّم تحت النص المفرَّغ.
  ///
  /// عناوين الأقسام ("مهام"/"Tasks") نص واجهة فتتبع لغة التطبيق، أما
  /// العناصر نفسها فبيانات المستخدم — تتبع اتجاه محتواها عبر
  /// [TranscriptText] تمامًا مثل النص المفرَّغ.
  Widget _buildAnalysis(AppLocalizations t) {
    // ما نعرض شيئًا قبل وصول التفريغ: التحليل ما بدأ أصلًا.
    if (!(widget.transcript?.trim().isNotEmpty ?? false)) {
      return const SizedBox.shrink();
    }

    final analysis = widget.analysis;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_screenPadding, 12, _screenPadding, 0),
      child: GlassContainer(
        borderRadius: 24,
        opacity: 0.34,
        blur: 18,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: analysis == null
            ? _buildAnalysisPlaceholder(t.analysisPending, Icons.auto_awesome)
            : analysis.isEmpty
                // نتيجة فاضية حكم صحيح مو خطأ: تسجيل قصير بلا مهام. نقولها
                // صراحةً بدل ما نعرض أقسامًا فاضية أو نخترع محتوى.
                ? _buildAnalysisPlaceholder(
                    t.analysisEmpty, Icons.check_circle_outline)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // نفس خريطة الفئات الأربع تبع الخريطة الذهنية حرفيًا
                      // (`MindMapNode.color`): الفئة الواحدة لازم يكون لها لون
                      // واحد بكل الشاشات وإلا انهار الترميز اللوني من أصله.
                      _section(
                          t.analysisTasks,
                          analysis.tasks,
                          Icons.check_circle_outline,
                          MindropColors.categoryTeal),
                      _section(t.analysisGoals, analysis.goals,
                          Icons.flag_outlined, MindropColors.categoryAmber),
                      _section(
                          t.analysisIdeas,
                          analysis.ideas,
                          Icons.lightbulb_outline,
                          MindropColors.crimsonPrimaryContainer),
                      _topics(t.analysisTopics, analysis.topics),
                      _buildMapButton(t, analysis),
                    ],
                  ),
      ),
    );
  }

  /// مدخل الخريطة الذهنية.
  ///
  /// **ليش من هنا:** شاشة التسجيل هي البيت ولازم تبقى ضغطة واحدة للتسجيل،
  /// فما نزاحمها بأي شي. والخريطة لتسجيل بعينه، فمكانها الطبيعي هو الشاشة
  /// اللي أنت فيها داخل ذاك التسجيل — تحت نتيجته مباشرة. وما تظهر إلا لما
  /// يكون فيه محتوى فعلًا، فما فيه طريق يودّي لشاشة فاضية.
  Widget _buildMapButton(AppLocalizations t, RecordingAnalysis analysis) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton.icon(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => MindMapScreen(
              recordingId: widget.draft.id,
              centerLabel: DateFormat.jm(
                Localizations.localeOf(context).toString(),
              ).format(widget.draft.createdAt),
              analysis: analysis,
            ),
          ),
        ),
        icon: const Icon(Icons.hub_outlined, size: 18),
        label: Text(t.mindMapOpen),
        style: TextButton.styleFrom(
          // الدرجة الفاتحة لا الحيّة: هذا **نص** بحجم 13.5 على أسود،
          // و`crimsonPrimaryContainer` تباينه ضعيف بهذا المقاس.
          foregroundColor: MindropColors.crimsonPrimary,
          textStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildAnalysisPlaceholder(String text, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: MindropColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: MindropColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(
      String label, List<String> items, IconData icon, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TranscriptText(
                item,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: MindropColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// المواضيع وسوم قصيرة — عرضها كرقائق أوضح من قائمة رأسية.
  Widget _topics(String label, List<String> topics) {
    if (topics.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // «المواضيع» فئة رابعة كاملة مثل الثلاث اللي فوق، فتاخذ لونها
            // (`categoryRose`) لا الرمادي المحايد — كانت محايدة قبل التحوّل
            // فتقرأ كعنوان ثانوي بينما هي بنفس المستوى تمامًا.
            Icon(Icons.tag_rounded,
                size: 15, color: MindropColors.categoryRose),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: MindropColors.categoryRose,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final topic in topics)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: MindropColors.glass.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: MindropColors.glassBorder),
                ),
                child: TranscriptText(
                  topic,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: MindropColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimes() {
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: MindropColors.textSecondary,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    // الوقتان رموز زمنية مو نص لغوي — يبقيان LTR بكل اللغات عشان ما
    // ينقلب "01:20" إلى "20:01" بواجهة عربية.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatDuration(Duration(milliseconds: _positionMs)),
          textDirection: TextDirection.ltr,
          style: style,
        ),
        Text(
          _formatDuration(Duration(milliseconds: _totalMs)),
          textDirection: TextDirection.ltr,
          style: style,
        ),
      ],
    );
  }

  Widget _buildDock(AppLocalizations t) {
    if (_loadFailed) return const SizedBox(height: 40);

    final isPlaying = _controller.playerState.isPlaying;

    return Padding(
      padding: const EdgeInsets.only(bottom: 34, top: 10),
      child: Semantics(
        button: true,
        label: isPlaying ? t.a11yPauseRecording : t.a11yPlayRecording,
        child: GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                // نفس ترتيب زر التسجيل بالضبط (`record_button.dart`):
                // القرمزي الحيّ ثم الفاتح. الزران أخوان بالوظيفة —
                // فرق التدرّج بينهما يُقرأ كخلل لا كتمييز.
                colors: [
                  MindropColors.crimsonPrimaryContainer,
                  MindropColors.crimsonPrimary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: MindropColors.crimsonPrimaryContainer
                      .withValues(alpha: 0.42),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
