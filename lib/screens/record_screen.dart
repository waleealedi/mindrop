import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/recording_draft.dart';
import '../services/audio_recorder_service.dart';
import '../services/deletion_queue_service.dart';
import '../services/draft_store.dart';
import '../services/firestore_sync_service.dart';
import '../services/upload_queue_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import 'history_screen.dart';
import '../widgets/organic_waveform.dart';
import '../widgets/pulse_rings.dart';
import '../widgets/record_button.dart';

/// الشاشة الرئيسية: زر تسجيل واحد كبير، وموجة صوتية تؤكد إن الصوت واصل.
///
/// قرار تخطيط مقصود (Fitts's Law): الزر بأسفل الشاشة داخل "دوك" زجاجي
/// عائم، مو بالمنتصف. على شاشة بحجم S25 Ultra، منتصف الشاشة خارج مدى
/// الإبهام المريح — والزر لازم يكون قابلًا للضغط بدون نظر.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with WidgetsBindingObserver {
  final _recorderService = AudioRecorderService();
  final _uuid = const Uuid();

  RecorderState _state = RecorderState.idle;
  Timer? _uiTimer;
  Duration _elapsed = Duration.zero;
  String? _currentDraftId;
  int _pendingCount = 0;

  /// آخر مستوى صوت (للهالة النابضة حول الزر وللموجة).
  double _level = 0;

  StreamSubscription<RecorderState>? _stateSub;
  StreamSubscription<double>? _levelSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateSub =
        _recorderService.stateStream.listen((s) => setState(() => _state = s));
    _refreshPendingCount();
    // يفرّغ أي رصيد قديم متراكم (تسجيلات من قبل ما نبني الرفع الحقيقي)
    // كل ما يفتح المستخدم التطبيق، بالإضافة لمحاولة الرفع بعد كل تسجيل
    // جديد بالأسفل.
    unawaited(_uploadPendingSafely());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _levelSub?.cancel();
    _uiTimer?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // التعامل مع المقاطعات: مكالمة واردة، قفل الشاشة، تصغير التطبيق.
    // نوقف التسجيل مؤقتًا بدل ما نخسره بالكامل.
    if (state == AppLifecycleState.paused &&
        _state == RecorderState.recording) {
      _pauseRecording();
    }

    // كل رجوع للتطبيق = محاولة رفع جديدة.
    //
    // بدون هذا، الرفع ما كان يُحاول إلا عند فتح التطبيق من الصفر أو بعد
    // تسجيل جديد — يعني لو فشل الرفع (سيرفر مطفي، لا إنترنت) يضطر
    // المستخدم يسجّل مقطعًا ما يبيه فقط عشان يحفّز إعادة المحاولة. الخروج
    // من التطبيق والرجوع له تصرّف طبيعي ومتاح دايمًا، فهو المحفّز الصحيح.
    if (state == AppLifecycleState.resumed) {
      unawaited(_uploadPendingSafely());
    }
  }

  // ---------------------------------------------------------------- منطق

  Future<void> _refreshPendingCount() async {
    final pending = await DraftStore.instance.pendingUpload();
    if (mounted) setState(() => _pendingCount = pending.length);
  }

  /// نعيد حساب عدّاد الانتظار بعد الرجوع: المستخدم يمكن حذف تسجيلات
  /// من شاشة الأفكار، فالرقم القديم يصير كذبًا على الشاشة.
  Future<void> _openHistory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
    await _refreshPendingCount();
  }

  Future<void> _handleTap() async {
    switch (_state) {
      case RecorderState.idle:
        await _startRecording();
      case RecorderState.recording:
        await _stopRecording();
      case RecorderState.paused:
        await _recorderService.resume();
        _startUiTimer();
        _listenToLevels();
    }
  }

  Future<void> _startRecording() async {
    final status = await _recorderService.checkPermission();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      _showPermissionDialog(permanentlyDenied: true);
      return;
    }

    _currentDraftId = _uuid.v4();
    final path = await DraftStore.instance.newRecordingPath(_currentDraftId!);

    try {
      await _recorderService.start(path);
      _startUiTimer();
      _listenToLevels();
    } on StateError {
      if (mounted) _showPermissionDialog(permanentlyDenied: false);
    } catch (_) {
      _showMessage((t) => t.recordStartFailed, isError: true);
    }
  }

  void _listenToLevels() {
    _levelSub?.cancel();
    _levelSub = _recorderService.levelStream().listen((v) {
      if (!mounted) return;
      setState(() => _level = v);
    });
  }

  Future<void> _pauseRecording() async {
    await _recorderService.pause();
    _uiTimer?.cancel();
    await _levelSub?.cancel();
    _levelSub = null;
    if (mounted) setState(() => _level = 0);
  }

  Future<void> _stopRecording() async {
    _uiTimer?.cancel();
    await _levelSub?.cancel();
    _levelSub = null;

    final result = await _recorderService.stop();

    if (result.path == null || _currentDraftId == null) {
      _showMessage((t) => t.recordNotSaved, isError: true);
      return;
    }

    final draft = RecordingDraft(
      id: _currentDraftId!,
      filePath: result.path!,
      createdAt: DateTime.now(),
      durationMs: result.duration.inMilliseconds,
    );
    await DraftStore.instance.add(draft);
    unawaited(_syncMetadataSafely(draft));
    unawaited(_uploadPendingSafely());

    if (!mounted) return;
    setState(() {
      _elapsed = Duration.zero;
      _currentDraftId = null;
      _level = 0;
    });
    await _refreshPendingCount();

    _showMessage((t) => t.savedLocally);
  }

  /// مزامنة سحابية "إضافية" فقط — أي فشل (لا إنترنت، Firebase غير جاهز،
  /// إلخ) يُتجاهل بصمت ولا يمس تدفق الحفظ المحلي أبدًا.
  Future<void> _syncMetadataSafely(RecordingDraft draft) async {
    try {
      await FirestoreSyncService.instance.syncMetadata(draft);
    } catch (_) {
      // تجاهل عمدًا.
    }
  }

  /// يحاول رفع كل التسجيلات المنتظرة بأفضل جهد ممكن (نفس فلسفة
  /// _syncMetadataSafely). كل فشل فردي [UploadQueueService] نفسه يعالجه
  /// (حالة failed لكل تسجيل على حدة) — هنا بس نحمي النداء من أي استثناء
  /// غير متوقع، ونحدّث عدّاد الانتظار بعد ما تخلص المحاولة كاملة.
  Future<void> _uploadPendingSafely() async {
    try {
      await UploadQueueService.instance.processPendingUploads();
    } catch (_) {
      // تجاهل عمدًا.
    }
    // نفس المحفّزات بالضبط تخدم طابور الحذف: فتح التطبيق، الرجوع له، أو
    // بعد كل جولة رفع. حذف فشل بلا شبكة يُستكمل هنا بلا أي تدخل يدوي.
    await DeletionQueueService.instance.flush();
    await _refreshPendingCount();
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _elapsed = _recorderService.elapsed());
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // -------------------------------------------------------------- رسائل

  /// شريط إشعار زجاجي داكن — بدل SnackBar الأبيض الافتراضي اللي كان
  /// يكسر الثيم الغامق بالكامل.
  ///
  /// ناخذ دالة اختيار للنص بدل النص نفسه عشان ما نلمس `context` إلا
  /// بعد التأكد إن الويدجت لسا حي — أغلب النداءات تجي بعد `await`.
  void _showMessage(
    String Function(AppLocalizations t) pick, {
    bool isError = false,
  }) {
    if (!mounted) return;
    final text = pick(AppLocalizations.of(context)!);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          padding: EdgeInsets.zero,
          content: GlassContainer(
            borderRadius: 20,
            opacity: 0.72,
            blur: 20,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_rounded,
                  size: 20,
                  color: isError
                      ? const Color(0xFFFF6B6B)
                      : MindropColors.neonTeal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: MindropColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  void _showPermissionDialog({required bool permanentlyDenied}) {
    final t = AppLocalizations.of(context)!;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.micPermissionTitle),
        content: Text(
          permanentlyDenied ? t.micPermissionBlocked : t.micPermissionRationale,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (permanentlyDenied) {
                openAppSettings();
              } else {
                _startRecording();
              }
            },
            child: Text(permanentlyDenied ? t.openSettings : t.allow),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- بناء

  @override
  Widget build(BuildContext context) {
    final isRecording = _state == RecorderState.recording;
    final isPaused = _state == RecorderState.paused;
    final isLive = isRecording || isPaused;

    return Scaffold(
      backgroundColor: MindropColors.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _buildStage(isLive: isLive, isRecording: isRecording),
              ),
              _buildDock(isRecording: isRecording, isPaused: isPaused),
            ],
          ),
        ),
      ),
    );
  }

  /// الشعار يُعامل كـ"علامة تجارية" لا كنص واجهة — يبقى لاتينيًا بكل
  /// اللغات وما يدخل ملفات الترجمة، بينما بقية النصوص تتبع لغة الجهاز.
  Widget _buildHeader() {
    final t = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MindropColors.accentSoft, MindropColors.accent],
              ),
              boxShadow: [
                BoxShadow(
                  color: MindropColors.accent.withValues(alpha: 0.45),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(
              Icons.water_drop_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Mindrop',
            // نثبّت الاتجاه LTR للشعار: بواجهة عربية RTL، الاسم اللاتيني
            // ينقلب ترتيبه مع علامات الترقيم لو تركناه يرث اتجاه الأب.
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: MindropColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded),
            iconSize: 22,
            color: MindropColors.textSecondary,
            // يغذّي التلميح وقارئ الشاشة معًا — IconButton يمرر النص
            // كـ Semantics label تلقائيًا.
            tooltip: t.historyOpenTooltip,
            visualDensity: VisualDensity.compact,
          ),
          if (_pendingCount > 0) _buildPendingChip(),
        ],
      ),
    );
  }

  /// الشريحة قابلة للضغط عمدًا: هي المكان الوحيد بالواجهة اللي يخبر
  /// المستخدم إن فيه شي معلّق، فهي المكان الطبيعي اللي يضغطه لما يبي
  /// يعيد المحاولة يدويًا — بدل ما ينتظر محفّزًا تلقائيًا.
  Widget _buildPendingChip() {
    final t = AppLocalizations.of(context)!;

    return Semantics(
      // بدون هذا قارئ الشاشة يقرأها نصًا عاديًا، فما يعرف المستخدم إنها
      // قابلة للضغط أصلًا. النص الموجود بالشريحة يصير تسمية الزر تلقائيًا.
      button: true,
      child: GestureDetector(
        onTap: _retryUploadsNow,
        // الشريحة نفسها ~30dp ارتفاعًا، وأقل مساحة لمس موصى بها 48dp
        // (Material + إرشادات أندرويد). نوسّع منطقة الضغط بدون ما نغيّر
        // شكل الشريحة: opaque يخلي الفراغ حولها يستقبل الضغط بدل ما يعبره.
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: _buildPendingChipBody(t),
          ),
        ),
      ),
    );
  }

  Future<void> _retryUploadsNow() async {
    _showMessage((t) => t.uploadRetrying);
    await _uploadPendingSafely();
  }

  Widget _buildPendingChipBody(AppLocalizations t) {
    return GlassContainer(
      borderRadius: 30,
      opacity: 0.5,
      blur: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MindropColors.neonTeal,
              boxShadow: [
                BoxShadow(
                  color: MindropColors.neonTeal.withValues(alpha: 0.7),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t.pendingUploads(_pendingCount),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: MindropColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage({required bool isLive, required bool isRecording}) {
    // نشتق من ثيم النصوص عشان يورث خط Urbanist. AnimatedDefaultTextStyle
    // يستبدل النمط الافتراضي بالكامل، فلو بنيناه من الصفر بيرجع لخط النظام.
    final timerStyle = Theme.of(context).textTheme.displayMedium!.copyWith(
          fontSize: 58,
          fontWeight: FontWeight.w200,
          letterSpacing: 2,
          height: 1,
          // أرقام بعرض ثابت: يمنع "رقصة" التايمر كل ثانية.
          fontFeatures: const [FontFeature.tabularFigures()],
          color: isLive
              ? MindropColors.textPrimary
              : MindropColors.textSecondary.withValues(alpha: 0.55),
        );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: timerStyle,
          child: Text(
            _formatDuration(_elapsed),
            // التايمر رموز زمنية مو نص لغوي — يبقى LTR بكل اللغات عشان
            // ما ينقلب "01:20" إلى "20:01" بواجهة عربية.
            textDirection: TextDirection.ltr,
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          height: 150,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 320),
            opacity: isLive ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: OrganicWaveform(level: _level, active: isRecording),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDock({required bool isRecording, required bool isPaused}) {
    final t = AppLocalizations.of(context)!;

    final status = isRecording
        ? t.recordStatusRecording
        : (isPaused ? t.recordStatusPaused : t.recordStatusIdle);
    final hint =
        isRecording ? t.hintRecording : (isPaused ? t.hintPaused : t.hintIdle);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: GlassContainer(
        borderRadius: 36,
        opacity: 0.42,
        blur: 22,
        padding: const EdgeInsets.only(top: 22, bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseRings(
              active: isRecording,
              level: _level,
              endRadius: 96,
              color: MindropColors.stitchPrimaryContainer,
              child: RecordButton(
                state: _state,
                level: _level,
                onTap: _handleTap,
              ),
            ),
            // سطران بدل سطر — بنية Stitch للحالة: عنوان يقول **أين أنت**،
            // وسطر أصغر يقول **ماذا تفعل**. السطر الثاني هو نص التلميح
            // القديم نفسه بلا تغيير، فما ضاع شي وما تكرر شي.
            //
            // ملاحظة على «لوحة زجاجية»: تصدير Stitch يضع هذي الحالة على
            // لوحة مستقلة. هنا الدوك **هو** تلك اللوحة أصلًا، فلو أضفنا
            // حاوية ثانية داخله لطلعت لوحة داخل لوحة. ما أضفنا أي ضباب
            // جديد ولا حاوية جديدة.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(status),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.16,
                      color: MindropColors.stitchPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: MindropColors.stitchOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
