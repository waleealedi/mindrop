import 'dart:math' as math;

import 'package:flutter/material.dart';
// `show Bidi` مقصود ومكمّل لقاعدة المشروع: استيراد intl كاملة يحجب
// `TextDirection` تبع Flutter بصنف intl نفسه.
import 'package:intl/intl.dart' show Bidi;

import '../services/firestore_sync_service.dart';
import '../theme/app_theme.dart';

/// نوع العقدة. مصمَّم ليكفي الخريطة الحالية (تسجيل واحد) والخريطة العابرة
/// للتسجيلات لاحقًا بدون تغيير — الفرق بينهما دالة تخطيط، لا نموذج جديد.
enum MindMapNodeKind { recording, category, task, goal, idea, topic }

extension MindMapNodeKindStyle on MindMapNodeKind {
  /// اللون من [MindropColors] حصرًا.
  Color get color => switch (this) {
        MindMapNodeKind.recording => MindropColors.accent,
        MindMapNodeKind.task => MindropColors.neonTeal,
        MindMapNodeKind.goal => MindropColors.accent,
        MindMapNodeKind.idea => MindropColors.neonBlue,
        MindMapNodeKind.topic => MindropColors.textSecondary,
        MindMapNodeKind.category => MindropColors.textSecondary,
      };

  /// أيقونة مميّزة لكل فئة.
  ///
  /// **اللون وحده ما يكفي** — نفس قاعدة أيقونات الحالة بشاشة الأفكار.
  /// عقد الفئات تحمل أيقونة **واسمًا مكتوبًا**، فمن عنده عمى ألوان يفرّق
  /// بين الفروع بالنص والشكل لا بالتدرّج اللوني.
  IconData? get icon => switch (this) {
        MindMapNodeKind.recording => Icons.graphic_eq_rounded,
        MindMapNodeKind.task => Icons.check_circle_outline,
        MindMapNodeKind.goal => Icons.flag_outlined,
        MindMapNodeKind.idea => Icons.lightbulb_outline,
        MindMapNodeKind.topic => Icons.tag_rounded,
        MindMapNodeKind.category => null,
      };
}

class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.label,
    required this.kind,
    this.payloadId,
  });

  final String id;
  final String label;
  final MindMapNodeKind kind;

  /// معرّف التسجيل اللي تنتمي له العقدة — تحتاجه الخريطة العابرة لاحقًا
  /// عشان الضغط على عنصر يوديك لتسجيله.
  final String? payloadId;
}

class MindMapEdge {
  const MindMapEdge(this.fromId, this.toId);
  final String fromId;
  final String toId;
}

/// رسم بياني عام: عقد وحواف، بدون أي علم بمصدرها.
///
/// هذا هو حد التوسّع المقصود: الرسّام والتفاعل والاتجاه النصي كلها تشتغل
/// على [MindMapGraph] وحده. إضافة الخريطة العابرة للتسجيلات لاحقًا = بانٍ
/// جديد + دالة تخطيط جديدة، بدون لمس طبقة العرض.
class MindMapGraph {
  const MindMapGraph({required this.nodes, required this.edges});

  final List<MindMapNode> nodes;
  final List<MindMapEdge> edges;

  bool get isEmpty => nodes.length <= 1;
}

/// يبني خريطة تسجيل واحد: التسجيل بالمركز، وفروع للفئات الأربع.
///
/// الفئات الفاضية تُحذف تمامًا — فرع "مهام" بلا مهام يشوّش ولا يضيف معنى.
MindMapGraph buildRecordingGraph({
  required String recordingId,
  required String centerLabel,
  required RecordingAnalysis analysis,
  required String tasksLabel,
  required String goalsLabel,
  required String ideasLabel,
  required String topicsLabel,
}) {
  final nodes = <MindMapNode>[];
  final edges = <MindMapEdge>[];

  const rootId = '__root__';
  nodes.add(MindMapNode(
    id: rootId,
    label: centerLabel,
    kind: MindMapNodeKind.recording,
    payloadId: recordingId,
  ));

  void addBranch(
    String categoryLabel,
    List<String> items,
    MindMapNodeKind itemKind,
  ) {
    if (items.isEmpty) return;
    final categoryId = 'cat_${itemKind.name}';
    nodes.add(MindMapNode(
      id: categoryId,
      label: categoryLabel,
      kind: MindMapNodeKind.category,
      payloadId: recordingId,
    ));
    edges.add(MindMapEdge(rootId, categoryId));

    for (var i = 0; i < items.length; i++) {
      final itemId = '${categoryId}_$i';
      nodes.add(MindMapNode(
        id: itemId,
        label: items[i],
        kind: itemKind,
        payloadId: recordingId,
      ));
      edges.add(MindMapEdge(categoryId, itemId));
    }
  }

  addBranch(tasksLabel, analysis.tasks, MindMapNodeKind.task);
  addBranch(goalsLabel, analysis.goals, MindMapNodeKind.goal);
  addBranch(ideasLabel, analysis.ideas, MindMapNodeKind.idea);
  addBranch(topicsLabel, analysis.topics, MindMapNodeKind.topic);

  return MindMapGraph(nodes: nodes, edges: edges);
}

// ---------------------------------------------------------------------------
// التخطيط
// ---------------------------------------------------------------------------

/// عقدة بعد التخطيط: موقعها وحجمها ورسّام نصها جاهزين.
///
/// نحتفظ بـ [TextPainter] هنا بدل ما نبنيه كل إطار: تخطيط النص أغلى جزء
/// بالرسم، وبناؤه مرة واحدة يخلي الرسم أثناء السحب مجرد رسم بكسل.
class LaidOutNode {
  LaidOutNode({
    required this.node,
    required this.center,
    required this.size,
    required this.textPainter,
    required this.color,
    this.iconPainter,
  });

  final MindMapNode node;
  final Offset center;
  final Size size;
  final TextPainter textPainter;
  final TextPainter? iconPainter;

  /// لون العقدة الفعلي. عقدة الفئة تاخذ لون عناصرها لا اللون المحايد، عشان
  /// الفرع كله يقرأ كوحدة بصرية واحدة.
  final Color color;

  Rect get rect => Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      );

  bool hitTest(Offset point) => rect.inflate(4).contains(point);
}

class MindMapLayout {
  const MindMapLayout({
    required this.nodes,
    required this.edges,
    required this.canvasSize,
  });

  final List<LaidOutNode> nodes;
  final List<MindMapEdge> edges;
  final Size canvasSize;

  LaidOutNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.node.id == id) return n;
    }
    return null;
  }

  LaidOutNode? hitTest(Offset point) {
    // من الآخر للأول: العقد المرسومة فوق تلتقط الضغط أولًا.
    for (var i = nodes.length - 1; i >= 0; i--) {
      if (nodes[i].hitTest(point)) return nodes[i];
    }
    return null;
  }
}

const double _maxLabelWidth = 148;
const double _nodePadH = 12;
const double _nodePadV = 9;
const double _hubRadius = 190;
const double _minItemGap = 74;

/// تخطيط شعاعي **حتمي بالكامل**: لا عشوائية ولا محاكاة فيزيائية، فنفس
/// المدخل يعطي نفس الشكل بالضبط كل مرة.
///
/// ليش شعاعي بدل force-directed: الرسم هنا شجرة من مستويين (تسجيل ←
/// فئات ← عناصر) وعددها ~15 عقدة. المحاكاة الفيزيائية تحل مشكلة ما عندنا،
/// وتضيف مشكلتين: نتيجة تختلف كل تشغيل ما لم تُبذَّر، وتكلفة إطار مستمرة.
MindMapLayout layoutRadial(MindMapGraph graph, {double textScale = 1.0}) {
  final laid = <LaidOutNode>[];

  TextPainter buildText(MindMapNode n, Color accent) {
    final isRoot = n.kind == MindMapNodeKind.recording;
    final isCategory = n.kind == MindMapNodeKind.category;

    // ------------------------------------------------------------------
    // اتجاه النص داخل الكانفس.
    //
    // `TextPainter` **يُلزمك** بتمرير textDirection ولا يرث أي شي من شجرة
    // الودجتس — ما فيه Directionality محيط يصله. فنكتشف الاتجاه من نص
    // العقدة نفسه، نفس قاعدة [TranscriptText] بالضبط: العناصر محتوى مستخدم
    // (عربي/إنجليزي مخلوط)، مو نص واجهة.
    // ------------------------------------------------------------------
    final isRtl = Bidi.detectRtlDirectionality(n.label);

    final tp = TextPainter(
      text: TextSpan(
        text: n.label,
        style: TextStyle(
          fontSize: isRoot ? 14 : (isCategory ? 12.5 : 13),
          height: 1.3,
          fontWeight: isRoot || isCategory ? FontWeight.w700 : FontWeight.w500,
          color: isCategory ? accent : MindropColors.textPrimary,
        ),
      ),
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: isRtl ? TextAlign.right : TextAlign.left,
      // سقف سطرين مع ellipsis: يمنع أي تسمية طويلة من تفجير حجم العقدة
      // أو تغطية جيرانها.
      maxLines: 2,
      ellipsis: '…',
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: _maxLabelWidth);

    // تخطيط بمرحلتين مقصود.
    //
    // `TextPainter.width` يرجّع **قيد** التخطيط لا عرض النص الفعلي، فلو
    // اكتفينا بمرحلة وحدة طلعت كل العقد بعرض 148 مهما قصرت تسمياتها.
    // نقيس العرض الطبيعي (`maxIntrinsicWidth`)، نحدّه بالسقف، ثم نعيد
    // التخطيط عليه — فتصير العقدة بقد نصها بالضبط ويبقى الالتفاف صحيحًا.
    final natural = math.min(tp.maxIntrinsicWidth, _maxLabelWidth);
    tp.layout(maxWidth: natural);
    return tp;
  }

  TextPainter? buildIcon(MindMapNode n, IconData? icon, Color accent) {
    if (icon == null) return null;
    return TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 13,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: accent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Size sizeFor(MindMapNode n, TextPainter tp, TextPainter? ip) {
    final iconW = ip == null ? 0.0 : ip.width + 6;
    return Size(
      tp.width + iconW + _nodePadH * 2,
      math.max(tp.height, ip?.height ?? 0) + _nodePadV * 2,
    );
  }

  // --- الجذر بالمركز ---
  final root = graph.nodes.firstWhere(
    (n) => n.kind == MindMapNodeKind.recording,
    orElse: () => graph.nodes.first,
  );
  final rootColor = root.kind.color;
  final rootText = buildText(root, rootColor);
  final rootIcon = buildIcon(root, root.kind.icon, rootColor);
  final rootSize = sizeFor(root, rootText, rootIcon);

  final categories =
      graph.nodes.where((n) => n.kind == MindMapNodeKind.category).toList();

  // كل فئة تاخذ قطاعًا زاويًا خاصًا بها، فما تتداخل عناصر فئتين أبدًا.
  final sector = categories.isEmpty ? 0.0 : (2 * math.pi) / categories.length;

  var minX = -rootSize.width / 2, maxX = rootSize.width / 2;
  var minY = -rootSize.height / 2, maxY = rootSize.height / 2;

  void track(Offset c, Size s) {
    minX = math.min(minX, c.dx - s.width / 2);
    maxX = math.max(maxX, c.dx + s.width / 2);
    minY = math.min(minY, c.dy - s.height / 2);
    maxY = math.max(maxY, c.dy + s.height / 2);
  }

  final placed = <String,
      ({
    Offset center,
    Size size,
    TextPainter tp,
    TextPainter? ip,
    Color color
  })>{};
  placed[root.id] = (
    center: Offset.zero,
    size: rootSize,
    tp: rootText,
    ip: rootIcon,
    color: rootColor,
  );

  for (var ci = 0; ci < categories.length; ci++) {
    final cat = categories[ci];
    // نبدأ من -90° عشان أول فرع يطلع فوق المركز — شكل ثابت ومتوقَّع.
    final centreAngle = -math.pi / 2 + sector * ci;

    // لون الفرع = لون عناصره.
    final branchColor = _categoryColorFor(cat, graph);
    final catText = buildText(cat, branchColor);
    final catIcon = buildIcon(cat, _categoryIconFor(cat, graph), branchColor);
    final catSize = sizeFor(cat, catText, catIcon);
    final catCenter = Offset(
      math.cos(centreAngle) * _hubRadius,
      math.sin(centreAngle) * _hubRadius,
    );
    placed[cat.id] = (
      center: catCenter,
      size: catSize,
      tp: catText,
      ip: catIcon,
      color: branchColor,
    );
    track(catCenter, catSize);

    final items = graph.edges
        .where((e) => e.fromId == cat.id)
        .map((e) => graph.nodes.firstWhere((n) => n.id == e.toId))
        .toList();
    if (items.isEmpty) continue;

    // نوسّع نصف القطر لو العناصر كثيرة، عشان طول القوس يكفيها بدون تلاصق.
    final needed = items.length * _minItemGap;
    final usableSector = sector * 0.78;
    final itemRadius = math.max(
      _hubRadius + 150,
      usableSector <= 0 ? 0 : needed / usableSector,
    );

    for (var i = 0; i < items.length; i++) {
      final t = items.length == 1 ? 0.5 : i / (items.length - 1);
      final angle = centreAngle - usableSector / 2 + usableSector * t;
      final itemText = buildText(items[i], items[i].kind.color);
      final itemIcon = buildIcon(items[i], null, items[i].kind.color);
      final itemSize = sizeFor(items[i], itemText, itemIcon);
      final c = Offset(
        math.cos(angle) * itemRadius,
        math.sin(angle) * itemRadius,
      );
      placed[items[i].id] = (
        center: c,
        size: itemSize,
        tp: itemText,
        ip: itemIcon,
        color: items[i].kind.color,
      );
      track(c, itemSize);
    }
  }

  // نزيح كل شي للإحداثيات الموجبة مع هامش، عشان الكانفس يبدأ من (0,0).
  const margin = 48.0;
  final dx = -minX + margin;
  final dy = -minY + margin;

  for (final n in graph.nodes) {
    final p = placed[n.id];
    if (p == null) continue;
    laid.add(LaidOutNode(
      node: n,
      center: p.center.translate(dx, dy),
      size: p.size,
      textPainter: p.tp,
      iconPainter: p.ip,
      color: p.color,
    ));
  }

  return MindMapLayout(
    nodes: laid,
    edges: graph.edges,
    canvasSize: Size(maxX - minX + margin * 2, maxY - minY + margin * 2),
  );
}

/// لون عقدة الفئة يُشتق من نوع عناصرها.
Color _categoryColorFor(MindMapNode category, MindMapGraph graph) {
  for (final e in graph.edges) {
    if (e.fromId != category.id) continue;
    return graph.nodes.firstWhere((n) => n.id == e.toId).kind.color;
  }
  return MindropColors.textSecondary;
}

/// أيقونة عقدة الفئة تُشتق من نوع عناصرها.
IconData? _categoryIconFor(MindMapNode category, MindMapGraph graph) {
  for (final e in graph.edges) {
    if (e.fromId != category.id) continue;
    final child = graph.nodes.firstWhere((n) => n.id == e.toId);
    return child.kind.icon;
  }
  return null;
}
