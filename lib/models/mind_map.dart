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

  /// اللون من [MindropColors] حصرًا — أدوار Obsidian Crimson.
  ///
  /// **توزيع القرمزي غير حرفي عمدًا.** القراءة الحرفية تعطي «الأفكار» دور
  /// `primary` (#FFB3B6)، لكن «المواضيع» تحمل #FFB4AB — الفرق بينهما وحدة
  /// واحدة بكل قناة، أي فئتان شقيقتان لا تُفرَّقان بالعين. فأخذت «الأفكار»
  /// `primary-container` القرمزي الحيّ (#E11D48)، وانتقل `primary` الفاتح
  /// للجذر.
  ///
  /// الجذر يستعمل لونه **للهالة فقط** (حدّه أبيض 10%)، وما يجلس أبدًا جنب
  /// «المواضيع» كشقيق — فتقارب #FFB3B6 و#FFB4AB ما يضرّ هناك.
  ///
  /// ولا لون مخترع: القيمتان الجديدتان كلتاهما من تصدير Crimson نفسه.
  Color get color => switch (this) {
        MindMapNodeKind.recording => MindropColors.crimsonPrimary,
        MindMapNodeKind.task => MindropColors.categoryTeal,
        MindMapNodeKind.goal => MindropColors.categoryAmber,
        MindMapNodeKind.idea => MindropColors.crimsonPrimaryContainer,
        MindMapNodeKind.topic => MindropColors.categoryRose,
        MindMapNodeKind.category => MindropColors.crimsonOutline,
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
// أشكال Stitch
// ---------------------------------------------------------------------------

/// كبسولة: مستطيل بنصف قطر = نصف الارتفاع.
///
/// **تغيّر عن الجولة السابقة:** كانت العقد العليا "كتلًا عضوية" (دائرة
/// مشوّهة بتشويه حتمي مبذور من معرّف العقدة). تصدير Stitch يحدّد لغة شكلية
/// واحدة صراحةً — `rounded-full` للعقد و`rounded-[3rem]` للجذر — يعني
/// كبسولات نظيفة لا كتلًا متموّجة. حذفنا التموّج بدل ما نخلطه بالاثنين:
/// شكل نصف-عضوي ما هو تسوية، هو مجرد شكل غير محسوم.
///
/// الطابع العضوي بقي حيث يحدّده Stitch فعلًا — بالمنحنيات الواصلة
/// (`Connectors: curved paths (splines), never straight`) وبالتخطيط الشعاعي.
Path pillPath(Size size, {double? radius}) {
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: size.width,
    height: size.height,
  );
  final r = radius ?? size.height / 2;
  return Path()
    ..addRRect(RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(r, size.height / 2)),
    ));
}

/// منحنى واصل بين عقدتين — خط مرسوم بسماكة ثابتة، لا شكل مملوء.
///
/// **تغيّر عن الجولة السابقة:** كان "غصنًا" متناقص السماكة (شكل مملوء من
/// حافتين). Stitch يرسمها `<path stroke-width="3" fill="none">` بتدرّج
/// لوني وشفافية 60% — خط رفيع منتظم. الخط الواحد أرخص أيضًا: مسار واحد
/// بدل ٢٦ نقطة محسوبة لكل حافة.
///
/// [t] يقصّ المنحنى عند نسبة من طوله — يحتاجه أنيميشن الدخول عشان الوصلات
/// تنمو للخارج مع العقد بدل ما تظهر كاملة فجأة. نقتطع بإعادة تقسيم بيزييه
/// (De Casteljau) فيبقى الشكل مطابقًا للأصل تمامًا على أي نسبة.
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
  // نبدأ من حافة العقدة لا من مركزها، فالخط ما يمر تحت الكبسولة.
  final a = from + dir * (fromRadius * 0.92);
  final b = to - dir * (toRadius * 0.92);

  final perp = Offset(-dir.dy, dir.dx);
  final bow = dist * 0.13;
  final c1 = a + (b - a) * 0.36 + perp * bow;
  final c2 = a + (b - a) * 0.72 + perp * (bow * 0.5);

  final end = t.clamp(0.0, 1.0);
  if (end >= 1.0) {
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
  }

  // De Casteljau: النصف الأول من المنحنى عند النسبة `end`.
  final p01 = Offset.lerp(a, c1, end)!;
  final p12 = Offset.lerp(c1, c2, end)!;
  final p23 = Offset.lerp(c2, b, end)!;
  final p012 = Offset.lerp(p01, p12, end)!;
  final p123 = Offset.lerp(p12, p23, end)!;
  final tip = Offset.lerp(p012, p123, end)!;

  return Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(p01.dx, p01.dy, p012.dx, p012.dy, tip.dx, tip.dy);
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
    required this.isRtl,
    this.iconPainter,
    this.countPainter,
    this.showDot = false,
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

  /// اتجاه نص العقدة، مكتشَفًا من محتواه هو.
  ///
  /// يحدّد **جهة النقطة الملوّنة**: Stitch يضعها قبل النص، و"قبل" بالعربي
  /// يمين لا يسار. بدون هذا تطلع نقطة العنصر العربي بالجهة الغلط من كبسولته.
  final bool isRtl;

  /// نقطة ملوّنة صغيرة تسبق النص — لغة Stitch لعقد العناصر
  /// (`w-3 h-3 rounded-full bg-{color}`).
  final bool showDot;

  MindMapLevel get level => node.kind.level;

  /// المسافة من المركز لحافة العقدة **باتجاه معيّن**.
  ///
  /// بدّلت `radius` الثابت السابق: مع الكبسولات الأفقية صار العرض أكبر
  /// بكثير من الارتفاع، فنصف قطر واحد يبدأ الوصلة بعيدًا عن الكبسولة رأسيًا
  /// أو داخلها أفقيًا. هذا يرجّع نقطة الحافة الحقيقية لكل اتجاه.
  double insetAlong(Offset dir) {
    final len = dir.distance;
    if (len < 1e-6) return size.height / 2;
    final ux = dir.dx.abs() / len;
    final uy = dir.dy.abs() / len;
    final tx = ux < 1e-6 ? double.infinity : (size.width / 2) / ux;
    final ty = uy < 1e-6 ? double.infinity : (size.height / 2) / uy;
    return math.min(tx, ty);
  }

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

// مسافات Stitch (وحدة 4: sm 8 / md 16 / lg 24). العناصر تاخذ `px-md py-sm`
// والجذر `px-lg py-md`، مصغَّرة قليلًا لتناسب كانفس جوال بدل شاشة عريضة.
const double _itemPadH = 14;
const double _itemPadV = 9;
const double _catPadH = 16;
const double _catPadV = 10;
const double _rootPadH = 22;
const double _rootPadV = 15;

/// قطر النقطة الملوّنة قبل نص العنصر، والفراغ بينها وبين النص.
const double _dotSize = 9;
const double _dotGap = 7;

/// الفراغ بين الأيقونة والنص داخل عقد الجذر والفئة.
const double _glyphGap = 8;

// يقرأها الرسّام عشان يضع المحتوى بنفس المقاسات اللي حُجزت وقت التخطيط.
// لو انفصل الرقمان طلع النص لا مركزيًا داخل كبسولته.
const double kNodeGlyphGap = _glyphGap;
const double kNodeDotSize = _dotSize;
const double kNodeDotGap = _dotGap;

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
    double? letterSpacing,
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
        style: MindropFonts.style(
          fontSize: fontSize,
          // العربية تحتاج سطرًا أعلى ~15% وإلا انقصّت التشكيلات من فوق —
          // نصّ عليها تصدير Crimson، ونعرف الاتجاه هنا أصلًا.
          height: MindropFonts.lineHeight(1.28, isRtl),
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
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

  /// تسمية الجذر: طابع زمني، خط أحادي العرض، سطر واحد متمركز.
  ///
  /// منفصلة عن [buildLabel] لأنها **ليست محتوى مستخدم**: وقت مُنسَّق تولّده
  /// الشاشة، فاتجاهه LTR دائمًا مثل بقية الأرقام بالتطبيق — لا يُكتشف من
  /// محتواه ولا ينقلب بواجهة عربية.
  TextPainter buildTimeLabel(
    MindMapNode n,
    Color color,
    double fontSize,
    FontWeight weight,
  ) {
    return TextPainter(
      text: TextSpan(
        text: n.label,
        style: MindropFonts.monoStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
      textScaler: TextScaler.linear(textScale),
    )..layout();
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
        style: MindropFonts.monoStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
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

  // الجذر: كبسولة أفقية بحدّ محايد وتوهج نيلي — نسخة Stitch حرفيًا
  // (`rounded-[3rem] border-white/10 shadow-[0_0_30px_rgba(128,131,255,.3)]`).
  // اللون المخزَّن هنا هو لون **التوهج** لا لون الحد.
  final rootColor = root.kind.color;
  // تسمية الجذر طابع زمني، فتاخذ الخط أحادي العرض (`data-tabular`).
  final rootText = buildTimeLabel(
    root,
    MindropColors.crimsonOnSurface,
    15,
    FontWeight.w500,
  );
  final rootIcon = buildIcon(root.kind.icon, rootColor, 19);
  final rootIconW = rootIcon == null ? 0.0 : rootIcon.width + _glyphGap;
  final rootSize = Size(
    math.max(140, rootText.width + rootIconW + _rootPadH * 2),
    math.max(rootText.height, rootIcon?.height ?? 0) + _rootPadV * 2,
  );

  final placed = <String, LaidOutNode>{};
  var minX = -rootSize.width / 2, maxX = rootSize.width / 2;
  var minY = -rootSize.height / 2, maxY = rootSize.height / 2;

  void track(Offset c, Size s) {
    minX = math.min(minX, c.dx - s.width / 2);
    maxX = math.max(maxX, c.dx + s.width / 2);
    minY = math.min(minY, c.dy - s.height / 2);
    maxY = math.max(maxY, c.dy + s.height / 2);
  }

  placed[root.id] = LaidOutNode(
    node: root,
    center: Offset.zero,
    size: rootSize,
    shape: pillPath(rootSize),
    textPainter: rootText,
    iconPainter: rootIcon,
    color: rootColor,
    entranceStart: 0,
    isRtl: Bidi.detectRtlDirectionality(root.label),
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

    // الفئة: كبسولة أفقية = أيقونة + اسم + عدّاد.
    //
    // كانت دائرة بمحتوى مكدّس رأسيًا. Stitch ما فيه دوائر عقد إطلاقًا —
    // كل عقده كبسولات أفقية، فالتمايز بين المستويات ينتقل من «شكل مختلف»
    // إلى الحجم والوزن وسماكة الحد ونوع الرمز المتصدّر (أيقونة للفئة،
    // نقطة للعنصر).
    //
    // الأيقونة تبقى مع الاسم المكتوب — Stitch يكتفي بنقطة ملوّنة، لكن
    // قاعدة المشروع تمنع اللون كإشارة وحيدة، والأيقونة إشارة أقوى من النقطة.
    final catText = buildLabel(
      cat,
      branchColor,
      13.5,
      FontWeight.w700,
      132,
      maxLines: 1,
      letterSpacing: 0.7, // label: +0.05em
    );
    final catIcon = buildIcon(childKind.icon, branchColor, 16);
    final catCount = buildCount(items.length, branchColor);

    final catIconW = catIcon == null ? 0.0 : catIcon.width + _glyphGap;
    final catSize = Size(
      catText.width + catIconW + catCount.width + _glyphGap + _catPadH * 2,
      math.max(catText.height, catIcon?.height ?? 0) + _catPadV * 2,
    );

    final catCenter = Offset(
      math.cos(centreAngle) * hubRadius,
      math.sin(centreAngle) * hubRadius,
    );

    placed[cat.id] = LaidOutNode(
      node: cat,
      center: catCenter,
      size: catSize,
      shape: pillPath(catSize),
      textPainter: catText,
      iconPainter: catIcon,
      countPainter: catCount,
      color: branchColor,
      entranceStart: 0.10 + ci * 0.045,
      isRtl: Bidi.detectRtlDirectionality(cat.label),
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
        MindropColors.crimsonOnSurfaceVariant,
        13,
        FontWeight.w500,
        _maxItemLabelWidth,
      );
      // النقطة الملوّنة تسبق النص (لغة Stitch)، فتحجز عرضها + فراغها.
      final itemSize = Size(
        itemText.width + _dotSize + _dotGap + _itemPadH * 2,
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
        shape: pillPath(itemSize),
        textPainter: itemText,
        color: item.kind.color,
        entranceStart: math.min(0.55, 0.26 + itemOrdinal * 0.022),
        isRtl: Bidi.detectRtlDirectionality(item.label),
        showDot: true,
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
        isRtl: p.isRtl,
        showDot: p.showDot,
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
      isRtl: p.isRtl,
      showDot: p.showDot,
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
      path: branchPath(
        from.center,
        from.insetAlong(to.center - from.center),
        to.center,
        to.insetAlong(from.center - to.center),
      ),
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
