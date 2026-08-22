import 'package:flutter/material.dart';
// `show Bidi` مقصود ومكمّل لقاعدة المشروع: استيراد intl كاملة يحجب
// `TextDirection` تبع Flutter بصنف intl نفسه. نوسّع قائمة show ولا نلغيها.
import 'package:intl/intl.dart' show Bidi;

/// نص مفرَّغ يستمد اتجاهه من محتواه هو، لا من لغة واجهة التطبيق.
///
/// **ليش:** لغة الواجهة ولغة التسجيل مستقلتان تمامًا — مستخدم واجهته
/// إنجليزية يسجّل بالعربي، والعكس. اللغة تُكتشف تلقائيًا لكل تسجيل وما
/// نمرّرها لـ Groq إطلاقًا، فما فيه أي رابط بين الاثنتين.
///
/// لو ورث النص اتجاه الواجهة، خوارزمية bidi تحسب مستوى الفقرة من الاتجاه
/// المحيط لا من المحتوى: نص عربي داخل فقرة LTR يطلع بترتيب بصري خاطئ،
/// والكلمات اللاتينية المدمجة ("back end") تتمزّق عبر نهايات الأسطر —
/// يطلع "end" بالجهة الغلط من السطر التالي.
///
/// **الاتجاه والمحاذاة لازم يمشون مع بعض:** نص عربي بمحاذاة يسار يبان
/// مكسورًا تقريبًا مثل النص المقلوب، فنشتق الاثنين من نفس الكشف.
class TranscriptText extends StatelessWidget {
  const TranscriptText(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;

  /// لما تُحدَّد، يُقصّ النص بـ ellipsis عند هذا الحد.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    // `detectRtlDirectionality` يرجّع bool عادي. نتجنّب
    // `estimateDirectionOfText` عمدًا: ترجّع `TextDirection` الخاص بـ intl،
    // وهو الصنف اللي نتفادى حجبه أصلًا.
    final isRtl = Bidi.detectRtlDirectionality(text);

    return Text(
      text,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: isRtl ? TextAlign.right : TextAlign.left,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: style,
    );
  }
}
