import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/mind_map.dart';
import '../services/firestore_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/mind_map_painter.dart';
import '../widgets/transcript_text.dart';

/// الخريطة الذهنية لتسجيل واحد: التسجيل بالمركز وفروع لمهامه وأهدافه
/// وأفكاره ومواضيعه.
///
/// **النطاق ولماذا:** الخريطة العابرة للتسجيلات (مواضيع كمحاور تربط عدة
/// تسجيلات) فكرة أقوى، لكن البيانات الفعلية اليوم ما تحتملها: 3 تسجيلات
/// فيها تحليل، و**صفر** مواضيع مشتركة بين أي تسجيلين. كانت بتطلع جزرًا
/// متفرقة بلا وصلة واحدة. الطبقة تحت (`MindMapGraph`) عامة، فإضافتها
/// لاحقًا = بانٍ ودالة تخطيط جديدة، بدون لمس هذي الشاشة.
class MindMapScreen extends StatefulWidget {
  const MindMapScreen({
    super.key,
    required this.recordingId,
    required this.centerLabel,
    required this.analysis,
  });

  final String recordingId;
  final String centerLabel;
  final RecordingAnalysis? analysis;

  @override
  State<MindMapScreen> createState() => _MindMapScreenState();
}

class _MindMapScreenState extends State<MindMapScreen>
    with TickerProviderStateMixin {
  final _controller = TransformationController();

  /// أنيميشن الدخول: العقد تنمو من المركز للخارج.
  ///
  /// **ليش أنيميشن أصلًا:** الخريطة كانت تظهر كاملة دفعة وحدة، فالمستخدم
  /// يقابل ١٥ عقدة في إطار واحد بلا أي دليل على الترتيب بينها. النمو من
  /// المركز يشرح البنية نفسها (تسجيل ← فئة ← عنصر) خلال أقل من ثانية.
  late final AnimationController _entrance;

  /// إبراز العقدة المحددة وخفوت البقية.
  late final AnimationController _selection;

  MindMapLayout? _layout;
  Size? _layoutViewport;
  double? _layoutTextScale;

  String? _selectedId;

  /// نبقي آخر تحديد أثناء انعكاس الأنيميشن، وإلا اختفت بطاقة التفاصيل
  /// فجأة بدل ما تخرج بنعومة.
  String? _lastSelectedId;

  bool _centered = false;

  /// هل حرّك المستخدم العرض عن وضعه الأولي؟ يقرّر ظهور زر إعادة التوسيط.
  /// `ValueNotifier` مقصود بدل `setState`: التحويل يتغيّر كل إطار أثناء
  /// السحب، وإعادة بناء الشاشة كلها ٦٠–١٢٠ مرة بالثانية عشان زر واحد هدر.
  final _transformed = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _selection = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    _entrance.dispose();
    _selection.dispose();
    _transformed.dispose();
    super.dispose();
  }

  void _onTransform() {
    final m = _controller.value;
    final moved = (m.getTranslation() - _homeMatrix.getTranslation()).length > 8 ||
        (m.getMaxScaleOnAxis() - _homeMatrix.getMaxScaleOnAxis()).abs() > 0.02;
    if (_transformed.value != moved) _transformed.value = moved;
  }

  Matrix4 _homeMatrix = Matrix4.identity();

  // ---------------------------------------------------------------- تخطيط

  /// يبني التخطيط مرة واحدة لكل (مقاس عرض × مقياس نص) — لا مرة كل إطار.
  MindMapLayout? _layoutFor(Size viewport, double textScale) {
    final analysis = widget.analysis;
    if (analysis == null || analysis.isEmpty) return null;

    if (_layout != null &&
        _layoutViewport == viewport &&
        _layoutTextScale == textScale) {
      return _layout;
    }

    final t = AppLocalizations.of(context)!;
    final graph = buildRecordingGraph(
      recordingId: widget.recordingId,
      centerLabel: widget.centerLabel,
      analysis: analysis,
      tasksLabel: t.analysisTasks,
      goalsLabel: t.analysisGoals,
      ideasLabel: t.analysisIdeas,
      topicsLabel: t.analysisTopics,
    );

    _layout = layoutOrganic(graph, textScale: textScale, viewport: viewport);
    _layoutViewport = viewport;
    _layoutTextScale = textScale;
    return _layout;
  }

  /// يضبط العرض الأولي ليُظهر الخريطة **كاملة** بدل ما يفتح على قصاصة منها.
  ///
  /// فرقان عن النسخة السابقة، كلاهما ردّ على عيب حقيقي:
  ///
  /// - كان السقف `1.0`، فخريطة قليلة المحتوى (عنصر واحد، ٣ عقد) تُرسم
  ///   بحجمها الطبيعي الصغير وسط شاشة فاضية — تقرأ كشي فشل تحميله. الحين
  ///   نسمح بالتكبير لـ1.9 فتملأ الحالة القليلة الشاشة وتبان **مقصودة**.
  /// - نترك هامشًا 6% بدل ما نلصق الحواف بحدود الشاشة.
  void _fitToViewport(Size viewport) {
    if (_centered || _layout == null) return;
    final canvas = _layout!.canvasSize;
    if (viewport.width <= 0 || canvas.width <= 0) return;

    final scale = math.min(
      1.9,
      math.min(viewport.width / canvas.width, viewport.height / canvas.height) *
          0.94,
    );
    final dx = (viewport.width - canvas.width * scale) / 2;
    final dy = (viewport.height - canvas.height * scale) / 2;

    _homeMatrix = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _controller.value = _homeMatrix.clone();
    _centered = true;

    if (_entrance.status == AnimationStatus.dismissed) _entrance.forward();
  }

  void _resetView() {
    _controller.value = _homeMatrix.clone();
    setState(() {
      _selectedId = null;
    });
    _selection.reverse();
  }

  void _handleTapUp(TapUpDetails d) {
    final hit = _layout?.hitTest(d.localPosition);
    // الضغط على الفراغ يلغي التحديد — خروج طبيعي بلا زر إضافي.
    final next = (hit == null || hit.node.id == _selectedId) ? null : hit.node.id;

    setState(() {
      if (next != null) _lastSelectedId = next;
      _selectedId = next;
    });

    if (next == null) {
      _selection.reverse();
    } else {
      _selection.forward();
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
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final layout = _layoutFor(viewport, textScale);

                    if (layout == null) return _buildEmpty(t);

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fitToViewport(viewport);
                    });

                    return Stack(
                      children: [
                        _buildCanvas(layout),
                        _buildDetail(t),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
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
              t.mindMapTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MindropColors.textPrimary,
              ),
            ),
          ),
          // يظهر فقط بعد ما يحرّك المستخدم العرض فعلًا — زر بلا وظيفة
          // حاليّة أسوأ من ما فيه زر (نفس قاعدة "حذف الكل" بشاشة الأفكار).
          ValueListenableBuilder<bool>(
            valueListenable: _transformed,
            builder: (context, moved, _) => AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: moved ? 1 : 0,
              child: IgnorePointer(
                ignoring: !moved,
                child: IconButton(
                  onPressed: _resetView,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  iconSize: 21,
                  color: MindropColors.textSecondary,
                  tooltip: t.mindMapResetView,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(MindMapLayout layout) {
    return InteractiveViewer(
      transformationController: _controller,
      // حدود سخيّة: الخريطة أكبر من الشاشة عادةً، فنسمح بسحبها بحرية.
      boundaryMargin: const EdgeInsets.all(600),
      minScale: 0.25,
      maxScale: 3.0,
      constrained: false,
      child: SizedBox(
        width: layout.canvasSize.width,
        height: layout.canvasSize.height,
        // GestureDetector **داخل** InteractiveViewer عمدًا: التحويل
        // جزء من شجرة العرض، فإحداثيات `localPosition` تجي محوّلة
        // أصلًا لفضاء الكانفس. ما نحتاج نعكس المصفوفة يدويًا.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _handleTapUp,
          // RepaintBoundary يخلي السحب يحرّك طبقة مرسومة مسبقًا بدل ما
          // يعيد رسم الكانفس كل إطار.
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_entrance, _selection]),
              builder: (context, _) {
                final animating =
                    _entrance.isAnimating || _selection.isAnimating;
                return CustomPaint(
                  size: layout.canvasSize,
                  isComplex: true,
                  // أثناء الحركة نخبر المحرك ألا يخزّن الطبقة نقطيًا —
                  // تخزين طبقة معقّدة يُعاد بناؤها كل إطار خسارة صافية.
                  // بعد السكون يرجع التخزين وينفع السحب والتكبير.
                  willChange: animating,
                  painter: MindMapPainter(
                    layout: layout,
                    selectedId: _selectedId,
                    entrance: _entrance.value,
                    selectionT: _selection.value,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// بطاقة تفاصيل العقدة المحددة.
  ///
  /// **ليش هذا هو فعل الضغط:** تسمية العقدة مقصوصة عند سطرين بالضرورة،
  /// فالحاجة الحقيقية عند الضغط هي رؤية النص كاملًا. الفتح على التسجيل ما
  /// يفيد — المستخدم جاي **من** التسجيل أصلًا. والتصفية بلا معنى بخريطة
  /// تسجيل واحد.
  Widget _buildDetail(AppLocalizations t) {
    return AnimatedBuilder(
      animation: _selection,
      builder: (context, _) {
        if (_selection.value <= 0.001) return const SizedBox.shrink();
        final id = _selectedId ?? _lastSelectedId;
        final node = id == null ? null : _layout?.nodeById(id);
        if (node == null) return const SizedBox.shrink();

        final label = switch (node.node.kind) {
          MindMapNodeKind.task => t.analysisTasks,
          MindMapNodeKind.goal => t.analysisGoals,
          MindMapNodeKind.idea => t.analysisIdeas,
          MindMapNodeKind.topic => t.analysisTopics,
          _ => t.mindMapRecordingNode,
        };

        final v = Curves.easeOutCubic.transform(_selection.value);

        return Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, (1 - v) * 26),
              child: _detailCard(node, label),
            ),
          ),
        );
      },
    );
  }

  // حاوية مصمتة لا زجاجية: تجلس فوق كانفس يُعاد رسمه، وما نبي
  // BackdropFilter بهذا المسار.
  Widget _detailCard(LaidOutNode node, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        // كانت #161616 مكتوبة حرفيًا. Crimson: بطاقات بزوايا 1rem.
        color: MindropColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: node.color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                node.node.kind.icon ?? Icons.notes_rounded,
                size: 14,
                color: node.color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: node.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // محتوى مستخدم: اتجاهه من نصه هو، مو من لغة الواجهة.
          TranscriptText(
            node.node.label,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: MindropColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 34,
              color: MindropColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 14),
            Text(
              t.mindMapEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: MindropColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
