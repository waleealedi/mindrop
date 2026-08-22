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

class _MindMapScreenState extends State<MindMapScreen> {
  final _controller = TransformationController();
  MindMapLayout? _layout;
  String? _selectedId;
  bool _centered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _buildLayout();
  }

  void _buildLayout() {
    final analysis = widget.analysis;
    if (analysis == null || analysis.isEmpty) {
      _layout = null;
      return;
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
    // مقياس النص من إعدادات الجهاز يدخل بالحساب: لو كبّر المستخدم الخط،
    // العقد تكبر معه بدل ما ينقص النص.
    _layout = layoutRadial(
      graph,
      textScale: MediaQuery.textScalerOf(context).scale(1),
    );
  }

  /// يضبط العرض الأولي ليُظهر الخريطة **كاملة** بدل ما يفتح على قصاصة منها.
  ///
  /// فتحها بمقياس 1 كانت العقد تنقص من الأطراف، فيضيع الشكل العام — وهو
  /// أهم ما تقدّمه خريطة أصلًا. نحسب مقياسًا يُدخل الكانفس كله بالشاشة
  /// (وما نكبّر أبعد من 1 لو كانت الخريطة صغيرة) ثم نتوسّط.
  void _fitToViewport(Size viewport) {
    if (_centered || _layout == null) return;
    final canvas = _layout!.canvasSize;
    if (viewport.width <= 0 || canvas.width <= 0) return;

    final scale = math.min(
      1.0,
      math.min(viewport.width / canvas.width, viewport.height / canvas.height),
    );
    final dx = (viewport.width - canvas.width * scale) / 2;
    final dy = (viewport.height - canvas.height * scale) / 2;

    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _centered = true;
  }

  void _handleTapUp(TapUpDetails d) {
    final hit = _layout?.hitTest(d.localPosition);
    setState(() {
      // الضغط على الفراغ يلغي التحديد — خروج طبيعي بلا زر إضافي.
      _selectedId =
          (hit == null || hit.node.id == _selectedId) ? null : hit.node.id;
    });
  }

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
                child: _layout == null
                    ? _buildEmpty(t)
                    : Stack(
                        children: [
                          _buildCanvas(),
                          if (_selectedId != null) _buildDetail(t),
                        ],
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
              t.mindMapTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MindropColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitToViewport(viewport);
        });

        return InteractiveViewer(
          transformationController: _controller,
          // حدود سخيّة: الخريطة أكبر من الشاشة عادةً، فنسمح بسحبها بحرية.
          boundaryMargin: const EdgeInsets.all(600),
          minScale: 0.25,
          maxScale: 3.0,
          constrained: false,
          child: SizedBox(
            width: _layout!.canvasSize.width,
            height: _layout!.canvasSize.height,
            // GestureDetector **داخل** InteractiveViewer عمدًا: التحويل
            // جزء من شجرة العرض، فإحداثيات `localPosition` تجي محوّلة
            // أصلًا لفضاء الكانفس. ما نحتاج نعكس المصفوفة يدويًا.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTapUp,
              // RepaintBoundary يخلي السحب يحرّك طبقة مرسومة مسبقًا بدل ما
              // يعيد رسم الكانفس كل إطار.
              child: RepaintBoundary(
                child: CustomPaint(
                  size: _layout!.canvasSize,
                  isComplex: true,
                  willChange: false,
                  painter: MindMapPainter(
                    layout: _layout!,
                    selectedId: _selectedId,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// بطاقة تفاصيل العقدة المحددة.
  ///
  /// **ليش هذا هو فعل الضغط:** تسمية العقدة مقصوصة عند سطرين بالضرورة،
  /// فالحاجة الحقيقية عند الضغط هي رؤية النص كاملًا. الفتح على التسجيل ما
  /// يفيد — المستخدم جاي **من** التسجيل أصلًا. والتصفية بلا معنى بخريطة
  /// تسجيل واحد.
  Widget _buildDetail(AppLocalizations t) {
    final node = _layout!.nodeById(_selectedId!);
    if (node == null) return const SizedBox.shrink();

    final label = switch (node.node.kind) {
      MindMapNodeKind.task => t.analysisTasks,
      MindMapNodeKind.goal => t.analysisGoals,
      MindMapNodeKind.idea => t.analysisIdeas,
      MindMapNodeKind.topic => t.analysisTopics,
      _ => t.mindMapRecordingNode,
    };

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      // حاوية مصمتة لا زجاجية: تجلس فوق كانفس يُعاد رسمه، وما نبي
      // BackdropFilter بهذا المسار.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161616).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
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
