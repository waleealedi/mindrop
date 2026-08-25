import crypto from 'node:crypto';

// ---------------------------------------------------------------------------
// منطق مطابقة المواضيع — **دوال خالصة بلا شبكة ولا Firestore**.
//
// مفصولة عمدًا عن التخزين والتضمين: هذا الملف هو الوحيد اللي فيه قرار
// «يلتصق بموضوع قائم ولا يبدأ موضوعًا جديدًا»، فيمكن اختباره كاملًا بمتجهات
// مكتوبة يدويًا بلا مفتاح API ولا محاكي.
// ---------------------------------------------------------------------------

/// عتبة التشابه لاعتبار موضوعين نفس الموضوع.
///
/// ⚠️ **رقم مبدئي، مو مدروس.** تخمين أولي لسلّم `text-embedding-3-small`
/// على عبارات قصيرة (كلمة إلى ثلاث). ما فيه بيانات استخدام حقيقية تسنده
/// بعد، ولازم يُضبط أول ما تتوفر.
///
/// مكانه هنا بأعلى الملف مقصود: يتغيّر برقم واحد، ما ينحفر داخل منطق.
export const SIMILARITY_THRESHOLD = 0.83;

/// تشابه جيب التمام بين متجهين.
///
/// يرجّع 0 لأي مدخل غير صالح (طول مختلف، متجه صفري) بدل ما يرمي: خطأ هنا
/// يعني «ما نعرف»، و«ما نعرف» = ما نقترح ربطًا، وهذا التصرّف الآمن.
export function cosineSimilarity(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b)) return 0;
  if (a.length === 0 || a.length !== b.length) return 0;

  let dot = 0;
  let magA = 0;
  let magB = 0;
  for (let i = 0; i < a.length; i++) {
    const x = a[i];
    const y = b[i];
    if (typeof x !== 'number' || typeof y !== 'number') return 0;
    dot += x * y;
    magA += x * x;
    magB += y * y;
  }
  if (magA === 0 || magB === 0) return 0;

  const sim = dot / (Math.sqrt(magA) * Math.sqrt(magB));
  // نحمي من انفلات عددي بسيط يطلع 1.0000000002 فيكسر أي مقارنة صارمة.
  return Math.max(-1, Math.min(1, sim));
}

/// أقرب موضوع قائم لمتجه عنصر، أو `null` لو ما فيه مرشّح صالح.
export function bestMatch(vector, topics) {
  let best = null;
  for (const topic of topics ?? []) {
    const score = cosineSimilarity(vector, topic.embedding);
    if (best === null || score > best.score) {
      best = { topic, score };
    }
  }
  return best;
}

/// القرار لعنصر «موضوع» واحد.
///
/// - ما فوق العتبة → `create`: نبدأ موضوعًا جديدًا بلا أي تدخّل من المستخدم.
///   هذي الحالة الشائعة وما فيها لبس يُسأل عنه.
/// - فيه مرشّح فوق العتبة → `suggest`: **ما نربط تلقائيًا**. نكتب اقتراحًا
///   معلّقًا تعرضه الواجهة لاحقًا. الربط التلقائي هنا يعني دمج فكرتين
///   مختلفتين بصمت، وهذا أسوأ من سؤال واحد.
export function decideForItem(vector, topics, threshold = SIMILARITY_THRESHOLD) {
  const match = bestMatch(vector, topics);
  if (match === null || match.score < threshold) {
    return { action: 'create', score: match?.score ?? 0 };
  }
  return {
    action: 'suggest',
    topicId: match.topic.id,
    label: match.topic.label,
    score: match.score,
  };
}

/// متجه الموضوع بعد التحاق عنصر جديد به — متوسط متحرّك مرجّح بعدد العناصر.
///
/// ليش متوسط مو استبدال: الموضوع يمثّل عنقودًا، فمركزه يجب أن يزحف قليلًا مع
/// كل عضو جديد لا أن يقفز لآخر واحد التحق. `itemCount` هو الوزن.
export function mergedEmbedding(current, incoming, itemCount) {
  if (!Array.isArray(current) || current.length === 0) return incoming ?? null;
  if (!Array.isArray(incoming) || incoming.length !== current.length) {
    return current;
  }
  const n = Number.isFinite(itemCount) && itemCount > 0 ? itemCount : 1;
  return current.map((v, i) => (v * n + incoming[i]) / (n + 1));
}

/// معرّف ثابت لعنصر «موضوع» داخل تسجيل.
///
/// **ليش موجود أصلًا:** عناصر التحليل اليوم نصوص عارية بلا أي معرّف، وربط
/// موضوع دائم بعنصر يحتاج مؤشّرًا يصمد. الفهرس بالمصفوفة **لا يصلح**: أي
/// إعادة ترتيب أو إعادة كتابة جزئية تحوّل المؤشّر لعنصر آخر بصمت.
///
/// فنشتقّه من المحتوى: نفس (التسجيل + النص + رقم التكرار) يعطي نفس المعرّف
/// دائمًا، ويبقى صحيحًا لو تغيّر ترتيب المصفوفة. `occurrence` يفصل التكرار
/// لو ورد نفس النص مرتين بنفس التسجيل.
export function topicItemId(recordingId, text, occurrence = 0) {
  const normalized = String(text ?? '').trim().toLowerCase();
  return crypto
    .createHash('sha1')
    .update(`${recordingId}|${normalized}|${occurrence}`)
    .digest('hex')
    .slice(0, 16);
}

/// يبني معرّفات لكل عناصر «المواضيع» بتسجيل واحد، مع فصل التكرارات.
export function buildTopicItems(recordingId, topics) {
  const seen = new Map();
  return (topics ?? []).map((text) => {
    const key = String(text ?? '').trim().toLowerCase();
    const occurrence = seen.get(key) ?? 0;
    seen.set(key, occurrence + 1);
    return { itemId: topicItemId(recordingId, text, occurrence), text };
  });
}
