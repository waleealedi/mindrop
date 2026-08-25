// ---------------------------------------------------------------------------
// تضمين النصوص (embeddings) — لمطابقة المواضيع الدائمة فقط.
//
// **مزوّد جديد على المشروع، وهذا مقصود التنبيه له.** خط الصوت كله يمشي على
// Groq، وGroq ما يوفّر نقطة تضمين إطلاقًا. وOPENROUTER_API_KEY الموجود
// بالبيئة موقوف أصلًا (بوابة رصيد $0.50، راجع transcription.js). فهذي
// الميزة تحتاج مزوّدًا مو موجودًا بالمسار الحالي.
//
// **ما نفعّل أي اعتماد مدفوع بصمت:** بدون `OPENAI_API_KEY` بالبيئة، هذا
// الملف يرجّع `null` والخطوة كلها تتوقف بهدوء. لا خطأ، ولا تعطيل لأي شي
// قائم — فقط ما تُنشأ مواضيع. إضافة المفتاح قرار صاحب المشروع، لا قرارنا.
//
// ما أضفنا حزمة npm: `fetch` مدمج بـ Node 20+، ونفس أسلوب transcription.js
// وanalysis.js.
// ---------------------------------------------------------------------------

const OPENAI_URL = 'https://api.openai.com/v1/embeddings';

/// نموذج صغير ورخيص، كافٍ لعبارات من كلمة إلى ثلاث (وهي كل ما نضمّنه هنا).
const EMBEDDING_MODEL = 'text-embedding-3-small';

/// هل المزوّد مضبوط أصلًا؟ يُستعمل للخروج المبكر بلا ضجيج بالسجل.
export function embeddingsConfigured() {
  const key = process.env.OPENAI_API_KEY;
  return typeof key === 'string' && key.trim().length > 0;
}

/// يرجّع متجهًا لكل نص، أو `null` لو المزوّد غير مضبوط.
///
/// يرمي عند فشل حقيقي بالشبكة/الـAPI — المستدعي يلتقطه ويعامله كـ best-effort،
/// نفس سياسة بقية الكتابات السحابية.
export async function embedTexts(texts) {
  if (!embeddingsConfigured()) return null;
  const input = (texts ?? []).map((t) => String(t ?? '').trim()).filter(Boolean);
  if (input.length === 0) return [];

  const response = await fetch(OPENAI_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: EMBEDDING_MODEL, input }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`فشل التضمين (${response.status}): ${body.slice(0, 200)}`);
  }

  const data = await response.json();
  if (!Array.isArray(data.data) || data.data.length !== input.length) {
    throw new Error('رد تضمين غير متوقع: عدد المتجهات ما يطابق عدد النصوص.');
  }

  // الترتيب مضمون بالـAPI عبر `index`، لكن ما نعتمد عليه ضمنيًا — نرتّب صراحةً.
  return data.data
    .slice()
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
    .map((row) => row.embedding);
}
