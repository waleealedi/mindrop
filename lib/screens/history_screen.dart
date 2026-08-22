import 'dart:async';

import 'package:flutter/material.dart';
// `show DateFormat` مقصود: حزمة intl تصدّر صنف `TextDirection` خاص فيها
// يحجب `TextDirection` تبع Flutter لو استوردناها كاملة.
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/app_localizations.dart';
import '../models/recording_draft.dart';
import '../services/draft_store.dart';
import '../services/firestore_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/transcript_text.dart';
import 'playback_screen.dart';

/// شاشة "أفكارك": كل التسجيلات المحفوظة محليًا، حالة كل واحد منها ضمن
/// خط المعالجة، وإمكانية حذفه نهائيًا.
///
/// مصدر البيانات هو [DraftStore] المحلي وحده — الشاشة تشتغل كاملة بدون
/// إنترنت، تمامًا مثل شاشة التسجيل.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<RecordingDraft> _drafts = const <RecordingDraft>[];
  bool _loading = true;

  /// ما وصلنا من الباك-إند عبر Firestore، مفتاحه معرّف التسجيل.
  Map<String, RemoteRecording> _remote = const {};
  StreamSubscription<Map<String, RemoteRecording>>? _remoteSub;

  @override
  void initState() {
    super.initState();
    _load();
    _listenRemote();
  }

  @override
  void dispose() {
    // المستمع يعيش بعمر هذي الشاشة فقط — راجع تعليق _listenRemote.
    _remoteSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- منطق

  Future<void> _load() async {
    final drafts = await DraftStore.instance.all();
    if (!mounted) return;
    setState(() {
      _drafts = drafts;
      _loading = false;
    });
  }

  /// نراقب Firestore طول ما هذي الشاشة مفتوحة فقط، ونلغي الاشتراك عند
  /// الخروج.
  ///
  /// ليش مستمع حي بدل قراءة وحدة: التفريغ يجي بعد ثوانٍ من الرفع، فقراءة
  /// وحدة عند الفتح تعني إن المستخدم يفتح شاشة "أفكارك" ويشوف تسجيله بلا
  /// نص، ولازم يخرج ويرجع عشان يظهر. المستمع يخلي النص يوصل وهو يتفرّج.
  ///
  /// وليش مقصور على الشاشة بدل مستمع عام بالتطبيق: الفاتورة والبطارية.
  /// Firestore يحاسب على كل مستند يُسلَّم؛ مستمع دائم يظل يستقبل تحديثات
  /// والتطبيق بالخلفية بلا فايدة. هنا التكلفة = عدد التسجيلات مرة وحدة عند
  /// الفتح + مستند واحد لكل تغيير فعلي، وصفر لما تكون الشاشة مقفلة.
  ///
  /// أي فشل (لا إنترنت، Firebase غير مهيأ) يُتجاهل: القائمة نفسها تنبني من
  /// [DraftStore] المحلي، فالشاشة تشتغل كاملة بدون شبكة.
  Future<void> _listenRemote() async {
    try {
      final stream = await FirestoreSyncService.instance.watchRemote();
      _remoteSub = stream.listen((remote) {
        if (mounted) setState(() => _remote = remote);
      }, onError: (_) {});
    } catch (_) {
      // تجاهل عمدًا — العرض المحلي يكفي.
    }
  }

  /// الاستماع ما يغيّر أي مسودة، فما نحتاج نعيد تحميل القائمة بعد الرجوع.
  void _openPlayback(RecordingDraft draft) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaybackScreen(
          draft: draft,
          transcript: _remote[draft.id]?.transcript,
          analysis: _remote[draft.id]?.analysis,
        ),
      ),
    );
  }

  /// الحذف نهائي ويشمل ملف الصوت نفسه (انظر [DraftStore.remove])، ولهذا
  /// نطلب تأكيدًا صريحًا قبله — ما فيه تراجع بعده.
  Future<void> _confirmDelete(RecordingDraft draft) async {
    final t = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteConfirmTitle),
        content: Text(t.deleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await DraftStore.instance.remove(draft.id);
    await _load();
  }

  /// نفس فكرة [_confirmDelete] لكن لكل التسجيلات دفعة وحدة. عملية أخطر
  /// بكثير (26+ ملف مو ملف وحد)، فالنص والزر مفاتيح ترجمة منفصلة
  /// (deleteAll*) بدل إعادة استخدام نص الحذف العادي — ما نبي المستخدم
  /// يلخبط بين الاثنين.
  Future<void> _confirmDeleteAll() async {
    final t = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteAllConfirmTitle),
        content: Text(t.deleteAllConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              // نفس أحمر حالة "فشل الرفع" بالأسفل — نلوّن فعل الحذف
              // الجماعي بلون تحذير عمدًا، أقوى بصريًا من زر الحذف العادي.
              backgroundColor: const Color(0xFFFF6B6B),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.deleteAll),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await DraftStore.instance.removeAll();
    await _load();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// أيقونة ولون ونص لكل حالة معالجة.
  ///
  /// اللون يحمل المعنى الأساسي (أزرق = شغل جارٍ، فيروزي = تم، أحمر =
  /// فشل)، والنص يبقى المصدر الوحيد الموثوق — اللون وحده ما يكفي لمن
  /// عنده عمى ألوان.
  ({IconData icon, Color color, String label}) _statusVisual(
    RecordingStatus status,
    AppLocalizations t,
  ) {
    switch (status) {
      case RecordingStatus.recorded:
        return (
          icon: Icons.schedule,
          color: MindropColors.textSecondary,
          label: t.statusRecorded,
        );
      case RecordingStatus.uploading:
        return (
          icon: Icons.cloud_upload,
          color: MindropColors.neonBlue,
          label: t.statusUploading,
        );
      case RecordingStatus.uploaded:
        return (
          icon: Icons.cloud_done_outlined,
          color: MindropColors.neonTeal,
          label: t.statusUploaded,
        );
      case RecordingStatus.transcribing:
        return (
          icon: Icons.graphic_eq,
          color: MindropColors.neonBlue,
          label: t.statusTranscribing,
        );
      case RecordingStatus.analyzing:
        return (
          icon: Icons.auto_awesome,
          color: MindropColors.accent,
          label: t.statusAnalyzing,
        );
      case RecordingStatus.completed:
        return (
          icon: Icons.check_circle_outline,
          color: MindropColors.neonTeal,
          label: t.statusCompleted,
        );
      case RecordingStatus.failed:
        return (
          icon: Icons.error_outline,
          color: const Color(0xFFFF6B6B),
          label: t.statusFailed,
        );
    }
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
              _buildHeader(t),
              Expanded(child: _buildBody(t)),
            ],
          ),
        ),
      ),
    );
  }

  /// هيدر مخصص بدل `AppBar`: نفس أسلوب شاشة التسجيل — بدون شريط مادي
  /// يقطع الخلفية المتوهجة.
  Widget _buildHeader(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 20, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: MindropColors.textPrimary,
            // نص جاهز ومترجم من Flutter نفسه — ما يحتاج مفتاح ترجمة خاص.
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: 4),
          Text(
            t.historyTitle,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: MindropColors.textPrimary,
            ),
          ),
          const Spacer(),
          // يظهر بس لو فيه شيء نحذفه — زر معطّل بلا فايدة أسوأ من ما فيه زر.
          if (_drafts.isNotEmpty)
            IconButton(
              onPressed: _confirmDeleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              color: MindropColors.textSecondary,
              tooltip: t.deleteAll,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations t) {
    // قبل ما يرجع القرص بالنتيجة ما نعرض "لا يوجد أفكار" — وإلا ومض النص
    // لجزء من الثانية عند كل فتح ثم اختفى.
    if (_loading) return const SizedBox.shrink();

    if (_drafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            t.historyEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: MindropColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final localeName = Localizations.localeOf(context).toString();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _drafts.length,
      itemBuilder: (context, i) => _buildTile(_drafts[i], t, localeName),
    );
  }

  /// بطاقة تسجيل واحد.
  ///
  /// ملاحظة أداء مقصودة: [Container] عادي بشفافية بسيطة، **لا**
  /// `GlassContainer`. الضبابية الحقيقية (`BackdropFilter`) تعيد قراءة
  /// الطبقة اللي خلفها كل إطار، ولو تكررت داخل قائمة طويلة تنهار سلاسة
  /// التمرير. الزجاج الحقيقي محجوز للعناصر الثابتة المحدودة فقط.
  Widget _buildTile(
    RecordingDraft draft,
    AppLocalizations t,
    String localeName,
  ) {
    final remote = _remote[draft.id];
    // ما نفضّل السحابي على المحلي بشكل مطلق: السحابي يحمل كتابة `recorded`
    // قديمة من لحظة الإنشاء، فيقدر يكون متأخرًا عن المحلي ويرجّع تسجيلًا
    // مرفوعًا لحالة "بانتظار الرفع". نعرض الأبعد على الخط — القاعدة كاملة
    // بـ [mergedRecordingStatus].
    final visual = _statusVisual(
      mergedRecordingStatus(draft.status, remote?.status),
      t,
    );
    final createdAt = draft.createdAt;
    final date = DateFormat.yMMMd(localeName).format(createdAt);
    final time = DateFormat.jm(localeName).format(createdAt);

    const metaStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: MindropColors.textSecondary,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MindropColors.glass.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MindropColors.glassBorder),
      ),
      // يقصّ تموّج الضغط (ink) على الزوايا الدائرية بدل ما يطلع مربعًا.
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // الضغط على البطاقة يفتح شاشة الاستماع. زر الحذف مستثنى من
          // منطقة الضغط عمدًا: نية الحذف ما تفتح شاشة.
          Expanded(
            child: Material(
              // شفاف: وظيفته إعطاء InkWell سطحًا يرسم عليه التموّج فوق
              // خلفية البطاقة، مو تغيير اللون.
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openPlayback(draft),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: visual.color.withValues(alpha: 0.14),
                        ),
                        // لما يوصل النص المفرَّغ يصير هو العنوان وتبقى
                        // الحالة أيقونة فقط — بدون تسمية ما يقدر قارئ
                        // الشاشة يعرفها إطلاقًا.
                        child: Semantics(
                          label: visual.label,
                          child:
                              Icon(visual.icon, size: 20, color: visual.color),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // النص المفرَّغ يتصدّر البطاقة لما يوصل: هو
                            // "الفكرة" نفسها، والحالة تصير تفصيلًا ثانويًا.
                            // قبل وصوله تبقى الحالة هي العنوان عشان ما تطلع
                            // بطاقة بلا هوية.
                            if (remote?.hasTranscript ?? false)
                              // اتجاه النص من محتواه هو مو من لغة الواجهة
                              // (راجع [TranscriptText]). بقية البطاقة —
                              // التاريخ والمدة والحالة — تبقى على لغة
                              // التطبيق.
                              TranscriptText(
                                remote!.transcript!.trim(),
                                // سطرين كحد أقصى: يثبّت سقف ارتفاع البطاقة
                                // مهما طال التفريغ أو اختلف اتجاهه، فما
                                // ينكسر التخطيط ولا يتأثر أداء التمرير.
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: MindropColors.textPrimary,
                                ),
                              )
                            else
                              Text(
                                visual.label,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: MindropColors.textPrimary,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  _formatDuration(
                                      Duration(milliseconds: draft.durationMs)),
                                  // المدة رموز زمنية مو نص لغوي — تبقى LTR بكل اللغات
                                  // عشان ما تنقلب "01:20" إلى "20:01" بواجهة عربية.
                                  textDirection: TextDirection.ltr,
                                  style: metaStyle,
                                ),
                                const SizedBox(width: 7),
                                Container(
                                  width: 3,
                                  height: 3,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: MindropColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    // فاصل محايد اتجاهيًا: يشتغل بالعربي والإنجليزي
                                    // بدون ما نكتب علامة ترقيم خاصة بلغة وحدة.
                                    '$date · $time',
                                    style: metaStyle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: IconButton(
              onPressed: () => _confirmDelete(draft),
              icon: const Icon(Icons.delete_outline),
              iconSize: 21,
              color: MindropColors.textSecondary,
              tooltip: t.delete,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}
