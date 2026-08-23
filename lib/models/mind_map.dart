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

/// مستوى العقدة بالهرم. **ثلاثة مستويات، وكل واحد يبان مختلفًا فعلًا** —
/// مو مجرد فرق حجم بسيط.
///
/// المشكلة القديمة: المستويات الثلاثة كانت موجودة بالبيانات وبالمواضع
/// (مركز → نصف قطر 190 → نصف قطر 340+)، لكن الثلاثة كانت تُرسم بنفس
/// المستطيل المدوّر وبفروق مجهرية (نصف قطر زاوية 18 مقابل 14، خط 14
/// مقابل 12.5). فالعين تقرأ حلقتين مو ثلاث طبقات. الحل هنا **اختلاف
/// شكلي** لا حجمي فقط: كتلة عضوية كبيرة للمركز، كتلة متوسطة للفئة،
/// وكبسولة صغيرة بمقاس نصّها للعنصر.
enum MindMapLevel { root, category, item }

extension MindMapNodeKindStyle on MindMapNodeKind {
  MindMapLevel get level => switch (this) {
        MindMapNodeKind.recording => MindMapLevel.root,
        MindMapNodeKind.category => MindMapLevel.category,
        _ => MindMapLevel.item,
      };

  /// اللون من [MindropColors] حصرًا.
  ///
  /// أربع درجات متمايزة للفئات الأربع، ودرجة خامسة للمركز. `topic` كان
  /// رماديًا (`textSecondary`) فيقرأ كعقدة معطّلة بدل فرع له هوية، و`goal`
  /// كان يشارك المركز نفس البرتقالي فينمحي الفرق بين «الجذر» و«فرع».
  Color get color => switch (this) {
        MindMapNodeKind.recording => MindropColors.accent,
        MindMapNodeKind.task => MindropColors.neonTeal,
        MindMapNodeKind.goal => MindropColors.neonLime,
        MindMapNodeKind.idea => MindropColors.neonBlue,
        MindMapNodeKind.topic => MindropColors.neonPink,
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

  /// عدد العناصر الحقيقية (بلا الجذر ولا عقد الفئات) — يقرّر كثافة التخطيط.
  int get itemCount =>
      nodes.where((n) => n.kind.level == MindMapLevel.item).length;
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
// أشكال عضوية
// ---------------------------------------------------------------------------

/// كتلة عضوية: دائرة مشوّهة تشويهًا خفيفًا **حتميًا** (البذرة من معرّف
/// العقدة)، فنفس العقدة تطلع بنفس الشكل بالضبط كل تشغيل.
///
/// ليش مو دائرة مضبوطة: الدوائر المتطابقة تقرأ كمخطط بيانات. وليش مو
/// عشوائية وقت الرسم: أي عشوائية تعني شكلًا يتغيّر بين إطار وإطار، وتكسر
/// `shouldRepaint` كمرجع للمقارنة.
Path organicBlobPath(double radius, int seed) {
  const points = 7; // فردي: يمنع التماثل المرآتي اللي يرجّع إحساس الدائرة
  final phase = (seed % 360) * math.pi / 180;
  final ring = <Offset>[];

  for (var i = 0; i < points; i++) {
    final a = (i / points) * 2 * math.pi;
    // موجتان بترددين غير متناسبين — نفس حيلة أشرطة الموجة بشاشة التسجيل:
    // ما ترجع لنفس الوضع بشكل دوري ملحوظ.
    final wobble =
        0.055 * math.sin(a * 3 + phase) + 0.032 * math.cos(a * 2 - phase * 1.7);
    final r = radius * (1 + wobble);
    ring.add(Offset(math.cos(a) * r, math.sin(a) * r));
  }

  return _closedSpline(ring);
}

/// كبسولة العنصر: مستطيل بنصف قطر = نصف الارتفاع (شكل حبّة دواء).
///
/// ليش كبسولة مو دائرة للعناصر: نص العنصر جملة كاملة من كلام المستخدم، مو
/// وسمًا من كلمتين مثل المراجع البصرية. دائرة بقد جملة تصير ضخمة وتاكل
/// الكانفس؛ الكبسولة تاخذ عرض نصّها بالضبط وتبقى الشكل الأنعم بعد الدائرة.
Path capsulePath(Size size) {
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: size.width,
    height: size.height,
  );
  return Path()
    ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)));
}

/// يمرّر منحنى مغلقًا ناعمًا (Catmull-Rom محوّل لبيزييه تكعيبي) على نقاط.
Path _closedSpline(List<Offset> p) {
  final n = p.length;
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = p[(i - 1 + n) % n];
    final p1 = p[i];
    final p2 = p[(i + 1) % n];
    final p3 = p[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// غصن متناقص السماكة بين عقدتين: عريض عند الأب، يرفّع لطرف رفيع عند
/// الابن — نفس لغة "الذيل" بالمراجع البصرية.
///
/// **ليش شكل مملوء مو خطًا بسماكة ثابتة:** الخط الثابت يقرأ كسلك بمخطط
/// شبكة. التناقص وحده هو اللي يعطي اتجاهًا بصريًا (من الأب للابن) بدون أي
/// سهم أو زخرفة.
///
/// [t] يقصّ الغصن عند نسبة من طوله — تحتاجه أنيميشن الدخول عشان الأغصان
/// تنمو للخارج مع العقد بدل ما تظهر كاملة فجأة.
Path branchPath(
  Offset from,
  double fromRadius,
  Offset to,
  double toRadius, {
  double t = 1.0,
}) {
  final delta = to - from;
  final dist = delta.distance;
  if (dist < 1) return Path();

  final dir = delta / dist;
  // ندخل قليلًا داخل حدود العقدتين عشان الغصن يندمج بالكتلة بدل ما يلمسها.
  final a = from + dir * (fromRadius * 0.86);
  final b = to - dir * (toRadius * 0.80);

  final perp = Offset(-dir.dy, dir.dx);
  final bow = dist * 0.13;
  final c1 = a + (b - a) * 0.36 + perp * bow;
  final c2 = a + (b - a) * 0.72 + perp * (bow * 0.5);

  final wA = math.min(fromRadius * 0.30, 15.0);
  final wB = math.max(toRadius * 0.13, 1.6);

  const steps = 13;
  final end = t.clamp(0.0, 1.0);
  final upper = <Offset>[];
  final lower = <Offset>[];

  for (var i = 0; i <= steps; i++) {
    final s = (i / steps) * end;
    final p = _cubic(a, c1, c2, b, s);
    final tangent = _cubicTangent(a, c1, c2, b, s);
    final len = tangent.distance;
    final nrm = len < 0.001 ? perp : Offset(-tangent.dy, tangent.dx) / len;
    // تناقص أُسّي: يبقى سميكًا قرب الأب ثم ينهار بسرعة — لو خلّيناه خطيًا
    // طلع مثلثًا هندسيًا بدل ذيل عضوي.
    final w = wB + (wA - wB) * math.pow(1 - s, 1.9).toDouble();
    upper.add(p + nrm * w);
    lower.add(p - nrm * w);
  }

  final path = Path()..moveTo(upper.first.dx, upper.first.dy);
  for (final o in upper.skip(1)) {
    path.lineTo(o.dx, o.dy);
  }
  for (final o in lower.reversed) {
    path.lineTo(o.dx, o.dy);
  }
  return path..close();
}

Offset _cubic(Offset a, Offset b, Offset c, Offset d, double t) {
  final u = 1 - t;
  return a * (u * u * u) +
      b * (3 * u * u * t) +
      c * (3 * u * t * t) +
      d * (t * t * t);
}

Offset _cubicTangent(Offset a, Offset b, Offset c, Offset d, double t) {
  final u = 1 - t;
  return (b - a) * (3 * u * u) + (c - b) * (6 * u * t) + (d - c) * (3 * t * t);
}

// ---------------------------------------------------------------------------
// التخطيط
// ---------------------------------------------------------------------------

/// عقدة بعد التخطيط: موقعها وشكلها ورسّام نصها جاهزون.
///
/// نحتفظ بـ [TextPainter] و[Path] هنا بدل ما نبنيهم كل إطار: تخطيط النص
/// أغلى جزء بالرسم، وبناؤه مرة واحدة يخلي الرسم أثناء السحب مجرد رسم بكسل.
class LaidOutNode {
  LaidOutNode({
    required this.node,
    required this.center,
    required this.size,
    required this.shape,
    required this.textPainter,
    required this.color,
    required this.entranceStart,
    this.iconPainter,
    this.countPainter,
  });

  final MindMapNode node;
  final Offset center;
  final Size size;

  /// الشكل بإحداثيات محلية حول (0,0) — الرسّام يزيحه ويقيسه بالكانفس.
  final Path shape;

  final TextPainter textPainter;
  final TextPainter? iconPainter;

  /// عدد عناصر الفرع، لعقد الفئات فقط. رقم = اتجاه LTR صريح دائمًا.
  final TextPainter? countPainter;

  final Color color;

  /// لحظة بدء ظهور العقدة ضمن أنيميشن الدخول (0..1 من زمن الأنيميشن).
  final double entranceStart;

  MindMapLevel get level => node.kind.level;

  /// نصف قطر تقريبي — نقطة الالتحام مع الأغصان.
  double get radius => math.max(size.width, size.height) / 2;

  Rect get rect => Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      );

  /// اختبار الضغط على **الشكل نفسه** لا على مستطيله: الكتل العضوية
  /// والكبسولات تترك زوايا فاضية، والضغط عليها كان يحدّد الجارة الغلط.
  /// مع ذلك نضمن حدًا أدنى للمساحة القابلة للمس (48dp) للعقد الصغيرة.
  bool hitTest(Offset point) {
    final local = point - center;
    if (shape.contains(local)) return true;
    return Rect.fromCenter(
      center: Offset.zero,
      width: math.max(size.width, 48),
      height: math.max(size.height, 48),
    ).contains(local);
  }
}

/// غصن بعد التخطيط.
class LaidOutEdge {
  LaidOutEdge({
    required this.fromId,
    required this.toId,
    required this.color,
    required this.path,
    required this.entranceStart,
  });

  final String fromId;
  final String toId;
  final Color color;

  /// الغصن كاملًا، مُحضَّرًا مسبقًا. يُستعمل بعد انتهاء أنيميشن الدخول؛
  /// أثناءه يعيد الرسّام بناءه لأن طرفيه يتحركان.
  final Path path;

  final double entranceStart;
}

class MindMapLayout {
  const MindMapLayout({
    required this.nodes,
    required this.edges,
    required this.canvasSize,
    required this.rootCenter,
  });

  final List<LaidOutNode> nodes;
  final List<LaidOutEdge> edges;
  final Size canvasSize;

  /// مركز الجذر — نقطة انطلاق أنيميشن الدخول.
  final Offset rootCenter;

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

/// أقل حصة زاوية مضمونة لكل فرع، مهما قلّت عناصره.
const double _minShare = 0.13;

/// هل تتقاطع عقدة بهذا المركز والمقاس مع أي عقدة موضوعة أصلًا؟
/// الهامش 14 يمنع "التلامس" اللي يبان تراكمًا حتى لو ما تقاطعت المستطيلات.
bool _collides(Iterable<LaidOutNode> placed, Offset center, Size size) {
  final rect = Rect.fromCenter(
    center: center,
    width: size.width + 14,
    height: size.height + 14,
  );
  for (final o in placed) {
    if (rect.overlaps(o.rect)) return true;
  }
  return false;
}

const double _maxItemLabelWidth = 152;
const double _itemPadH = 15;
const double _itemPadV = 10;
const double _margin = 56;

/// تخطيط شعاعي **حتمي بالكامل**: لا عشوائية ولا محاكاة فيزيائية، فنفس
/// المدخل يعطي نفس الشكل بالضبط كل مرة.
///
/// ليش شعاعي بدل force-directed: الرسم هنا شجرة من مستويين (تسجيل ←
/// فئات ← عناصر) وعددها ~15 عقدة. المحاكاة الفيزيائية تحل مشكلة ما عندنا،
/// وتضيف مشكلتين: نتيجة تختلف كل تشغيل ما لم تُبذَّر، وتكلفة إطار مستمرة.
///
/// ثلاثة قرارات تخطيط جديدة، كلها ردّ على عيوب حقيقية:
///
/// 1. **بيضاوي لا دائري** ([viewport]). التخطيط الدائري ينتج كانفسًا شبه
///    مربّع، والشاشة ~9:19.5 — فاحتواء مربع داخل مستطيل طويل يترك فراغًا
///    رأسيًا ضخمًا أعلى وأسفل بالضرورة. نمدّ المحور الرأسي بنسبة الشاشة
///    نفسها فيصير الكانفس بنفس تناسبها تقريبًا.
/// 2. **قطاع بحجم محتواه.** كانت القطاعات متساوية (٢π/عدد الفئات) مهما
///    اختلف عدد العناصر، فيتزاحم فرع فيه ٦ عناصر وييبس فرع فيه واحد.
///    الحين القطاع يتناسب مع عدد العناصر.
/// 3. **أنصاف أقطار تتبع الكثافة.** خريطة فيها ٣ عقد كانت ترسم على كانفس
///    بمقاس خريطة فيها ٢٠، فتطلع نقطًا تائهة بفراغ — تقرأ كعطل مو كحالة
///    قليلة مقصودة. الحين المسافات تنكمش مع قلة المحتوى.
MindMapLayout layoutOrganic(
  MindMapGraph graph, {
  double textScale = 1.0,
  Size viewport = const Size(400, 700),
}) {
  // ---------------------------------------------------------------- رسّامون

  TextPainter buildLabel(
    MindMapNode n,
    Color color,
    double fontSize,
    FontWeight weight,
    double maxWidth, {
    int maxLines = 2,
    TextAlign? forceAlign,
  }) {
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
          fontSize: fontSize,
          height: 1.28,
          fontWeight: weight,
          color: color,
        ),
      ),
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: forceAlign ?? (isRtl ? TextAlign.right : TextAlign.left),
      maxLines: maxLines,
      ellipsis: '…',
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: maxWidth);

    // تخطيط بمرحلتين مقصود.
    //
    // `TextPainter.width` يرجّع **قيد** التخطيط لا عرض النص الفعلي، فلو
    // اكتفينا بمرحلة وحدة طلعت كل العقد بعرض السقف مهما قصرت تسمياتها.
    // نقيس العرض الطبيعي (`maxIntrinsicWidth`)، نحدّه بالسقف، ثم نعيد
    // التخطيط عليه — فتصير العقدة بقد نصها بالضبط ويبقى الالتفاف صحيحًا.
    final natural = math.min(tp.maxIntrinsicWidth, maxWidth);
    tp.layout(maxWidth: natural);
    return tp;
  }

  TextPainter? buildIcon(IconData? icon, Color color, double size) {
    if (icon == null) return null;
    return TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScale),
    )..layout();
  }

  /// الرقم رموز عددية مو نص لغوي — LTR صريح بكل اللغات، نفس قاعدة
  /// التايمر ومدة التسجيل.
  TextPainter buildCount(int value, Color color) {
    return TextPainter(
      text: TextSpan(
        text: '$value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScale),
    )..layout();
  }

  // ------------------------------------------------------------- بنية الرسم

  final root = graph.nodes.firstWhere(
    (n) => n.kind == MindMapNodeKind.recording,
    orElse: () => graph.nodes.first,
  );
  final categories =
      graph.nodes.where((n) => n.kind == MindMapNodeKind.category).toList();

  List<MindMapNode> childrenOf(String id) => graph.edges
      .where((e) => e.fromId == id)
      .map((e) => graph.nodes.firstWhere((n) => n.id == e.toId))
      .toList();

  final itemsByCategory = {
    for (final c in categories) c.id: childrenOf(c.id),
  };

  // الكثافة: كم عنصرًا فعليًا بالخريطة كلها. تقرّر المسافات كلها.
  final density = graph.itemCount.clamp(1, 18);
  final spread = (density - 1) / 17; // 0 = أقل ما يمكن، 1 = مزدحمة

  final hubRadius = 118 + 92 * spread; // 118..210
  final itemGap = 62 + 20 * spread; // 62..82

  // ------------------------------------------------------------------ الجذر

  final rootColor = root.kind.color;
  final rootText = buildLabel(
    root,
    MindropColors.textPrimary,
    15,
    FontWeight.w700,
    120,
    maxLines: 1,
    forceAlign: TextAlign.center,
  );
  final rootIcon = buildIcon(root.kind.icon, rootColor, 20);
  final rootRadius = math.max(
    58.0,
    math.max(rootText.width, 92) / 2 + 16,
  );

  final placed = <String, LaidOutNode>{};
  var minX = -rootRadius, maxX = rootRadius;
  var minY = -rootRadius, maxY = rootRadius;

  void track(Offset c, Size s) {
    minX = math.min(minX, c.dx - s.width / 2);
    maxX = math.max(maxX, c.dx + s.width / 2);
    minY = math.min(minY, c.dy - s.height / 2);
    maxY = math.max(maxY, c.dy + s.height / 2);
  }

  placed[root.id] = LaidOutNode(
    node: root,
    center: Offset.zero,
    size: Size.square(rootRadius * 2),
    shape: organicBlobPath(rootRadius, root.id.hashCode),
    textPainter: rootText,
    iconPainter: rootIcon,
    color: rootColor,
    entranceStart: 0,
  );

  // ------------------------------------------------- قطاعات بحجم محتوياتها

  // القطاع يتناسب مع عدد العناصر، **لكن بحد أدنى مضمون** لكل فئة.
  //
  // التناسب الصافي وحده انكسر على بيانات حقيقية: تسجيل فيه ٨ أفكار مقابل
  // مهمة واحدة يعطي المهمة ٢١° فقط، فعنصرها الوحيد يلتصق بعناصر الفرع
  // المجاور ويقرأ كأنه تابع له. الصيغة أدناه تحجز `_minShare` لكل فرع ثم
  // توزّع الباقي بالتناسب — مجموعها يبقى ١ بالضبط.
  final counts = [
    for (final c in categories) math.max(1, itemsByCategory[c.id]!.length),
  ];
  final countSum = counts.fold<int>(0, (a, b) => a + b);
  final free = math.max(0.0, 1 - categories.length * _minShare);
  final shares = [
    for (final c in counts) _minShare + free * (c / countSum),
  ];

  final edges = <LaidOutEdge>[];
  var itemOrdinal = 0;
  var cursor = -math.pi / 2; // نبدأ من فوق: شكل ثابت ومتوقَّع كل مرة

  for (var ci = 0; ci < categories.length; ci++) {
    final cat = categories[ci];
    final items = itemsByCategory[cat.id]!;
    final childKind = items.isEmpty ? MindMapNodeKind.topic : items.first.kind;
    final branchColor = childKind.color;

    final sector = shares[ci] * 2 * math.pi;
    final centreAngle = cursor + sector / 2;
    cursor += sector;

    // حجم عقدة الفئة يكبر مع عدد عناصرها — نفس لغة "الفقاعة الأكبر تعني
    // وزنًا أكبر" بالمراجع البصرية.
    final catRadius = 40.0 + math.min(items.length, 8) * 2.6;
    final catText = buildLabel(
      cat,
      MindropColors.textPrimary,
      12.5,
      FontWeight.w700,
      catRadius * 1.7,
      maxLines: 1,
      forceAlign: TextAlign.center,
    );
    final catIcon = buildIcon(childKind.icon, branchColor, 15);
    final catCount = buildCount(items.length, branchColor);

    final catCenter = Offset(
      math.cos(centreAngle) * hubRadius,
      math.sin(centreAngle) * hubRadius,
    );
    final catSize = Size.square(catRadius * 2);

    placed[cat.id] = LaidOutNode(
      node: cat,
      center: catCenter,
      size: catSize,
      shape: organicBlobPath(catRadius, cat.id.hashCode),
      textPainter: catText,
      iconPainter: catIcon,
      countPainter: catCount,
      color: branchColor,
      entranceStart: 0.10 + ci * 0.045,
    );
    track(catCenter, catSize);

    if (items.isEmpty) continue;

    // نصف القطر يوسّع نفسه لو طول القوس ما يكفي العناصر بدون تلاصق.
    final usableSector = sector * 0.80;
    final needed = items.length * itemGap;
    final itemRadius = math.max(
      hubRadius + 128,
      usableSector <= 0 ? 0 : needed / usableSector,
    );

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final t = items.length == 1 ? 0.5 : i / (items.length - 1);
      final angle = centreAngle - usableSector / 2 + usableSector * t;

      final itemText = buildLabel(
        item,
        MindropColors.textPrimary,
        13,
        FontWeight.w500,
        _maxItemLabelWidth,
      );
      final itemSize = Size(
        itemText.width + _itemPadH * 2,
        itemText.height + _itemPadV * 2,
      );

      // إزاحة شعاعية متناوبة: العناصر ما تجلس على حلقة مثالية، فيقل
      // التلاصق ويطلع الفرع كعنقود عضوي بدل صف مسطرة.
      final stagger = (i.isEven ? 0.0 : 1.0) * 18 - (i % 3) * 6;

      // ثم دفع شعاعي للخارج لين تنفكّ أي تقاطع فعلي.
      //
      // **ليش ما كفى التباعد الزاوي وحده:** طول القوس بين عنصرين يُحسب من
      // زاوية ثابتة، بينما عرض الكبسولة يجي من نص المستخدم — جملة طويلة
      // تطلع بعرض 182 بينما القوس المتاح لها ~95. النتيجة كانت كبسولتين
      // متراكبتين حرفيًا بفرع «الأفكار». الدفع للخارج يحلّها بلا عشوائية
      // وبلا محاكاة: نفس المدخل يعطي نفس النتيجة.
      var r = itemRadius + stagger;
      var c = Offset(math.cos(angle) * r, math.sin(angle) * r);
      var guard = 0;
      while (guard++ < 40 && _collides(placed.values, c, itemSize)) {
        r += 11;
        c = Offset(math.cos(angle) * r, math.sin(angle) * r);
      }

      placed[item.id] = LaidOutNode(
        node: item,
        center: c,
        size: itemSize,
        shape: capsulePath(itemSize),
        textPainter: itemText,
        color: item.kind.color,
        entranceStart: math.min(0.55, 0.26 + itemOrdinal * 0.022),
      );
      track(c, itemSize);
      itemOrdinal++;
    }
  }

  // ------------------------------------------------- تمديد رأسي حسب الشاشة

  // **العيب اللي يعالجه هذا المقطع:** التخطيط الشعاعي ينتج كانفسًا نسبته
  // ~1:1، والشاشة ~1:1.9. احتواء مربع داخل مستطيل طويل يحدّه العرض دائمًا،
  // فيبقى أعلى الشاشة وأسفلها فاضيًا مهما صغّرنا أو كبّرنا.
  //
  // نمدّ المحور الرأسي **بعد** التوضيع لا قبله، وبمقدار محسوب من النسبة
  // الفعلية للكانفس بعد ما عرفناها — لأن العرض النهائي يعتمد على عرض
  // الكبسولات (نص المستخدم)، وهو مجهول قبل القياس. التمديد يحرّك المراكز
  // فقط ولا يمسّ أحجام العقد، فما ينشوّه أي شكل ولا يحتاج إعادة قياس نص.
  final rawW = maxX - minX;
  final rawH = maxY - minY;
  final wantAspect =
      viewport.width <= 0 ? 1.0 : viewport.height / viewport.width;
  final haveAspect = rawW <= 0 ? 1.0 : rawH / rawW;
  // السقف 1.9: أبعد من كذا يبان الشكل بيضاويًا مسحوبًا بدل ما يقرأ شعاعيًا.
  final stretch = (wantAspect / haveAspect).clamp(1.0, 1.9);

  if (stretch > 1.0) {
    final stretched = <String, LaidOutNode>{};
    minY = double.infinity;
    maxY = double.negativeInfinity;
    for (final entry in placed.entries) {
      final p = entry.value;
      final c = Offset(p.center.dx, p.center.dy * stretch);
      stretched[entry.key] = LaidOutNode(
        node: p.node,
        center: c,
        size: p.size,
        shape: p.shape,
        textPainter: p.textPainter,
        iconPainter: p.iconPainter,
        countPainter: p.countPainter,
        color: p.color,
        entranceStart: p.entranceStart,
      );
      minY = math.min(minY, c.dy - p.size.height / 2);
      maxY = math.max(maxY, c.dy + p.size.height / 2);
    }
    placed
      ..clear()
      ..addAll(stretched);
  }

  // ------------------------------------------------------------ إزاحة للموجب

  final dx = -minX + _margin;
  final dy = -minY + _margin;

  final laid = <LaidOutNode>[];
  final shifted = <String, LaidOutNode>{};
  for (final n in graph.nodes) {
    final p = placed[n.id];
    if (p == null) continue;
    final moved = LaidOutNode(
      node: p.node,
      center: p.center.translate(dx, dy),
      size: p.size,
      shape: p.shape,
      textPainter: p.textPainter,
      iconPainter: p.iconPainter,
      countPainter: p.countPainter,
      color: p.color,
      entranceStart: p.entranceStart,
    );
    laid.add(moved);
    shifted[n.id] = moved;
  }

  // الأغصان تُبنى **بعد** الإزاحة عشان مساراتها بإحداثيات الكانفس النهائية.
  for (final e in graph.edges) {
    final from = shifted[e.fromId];
    final to = shifted[e.toId];
    if (from == null || to == null) continue;
    edges.add(LaidOutEdge(
      fromId: e.fromId,
      toId: e.toId,
      color: to.color,
      path: branchPath(from.center, from.radius, to.center, to.radius),
      entranceStart: to.entranceStart,
    ));
  }

  return MindMapLayout(
    nodes: laid,
    edges: edges,
    canvasSize: Size(maxX - minX + _margin * 2, maxY - minY + _margin * 2),
    rootCenter: Offset.zero.translate(dx, dy),
  );
}
