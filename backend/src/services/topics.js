import { embedTexts, embeddingsConfigured } from './embeddings.js';
import { buildTopicItems, decideForItem } from './topicMatcher.js';
import { createTopic, listTopics, saveTopicLinks } from './topicStore.js';

// ---------------------------------------------------------------------------
// ربط عناصر «المواضيع» بمواضيع دائمة عابرة للتسجيلات.
//
// **يشتغل بعد ما يُكتب التحليل، ولا يمس خط المعالجة القائم إطلاقًا.**
// البنية هنا سيرفر Express بلا حالة، والمعالجة كلها تجري **بعد** ما رجع الرد
// 200 للجوال (راجع `transcribeInBackground` بـ recordings.js). يعني هذي
// الخطوة ما تضيف ولا ميلي ثانية لمسار الحفظ اللي يحسّه المستخدم — الرد طلع
// من زمان.
//
// (ما فيه Cloud Functions بالمشروع ولا مجلد `functions/`، فما فيه مشغّل
// Firestore نعلّق عليه. البنية الفعلية هي اللي حدّدت مكان الخطوة.)
//
// الفشل هنا **يُبتلع دائمًا**: الميزة إضافية، وأسوأ نتيجة لفشلها ألا يُنشأ
// موضوع. تحليل التسجيل ونصّه محفوظان قبل أن نصل إلى هنا.
// ---------------------------------------------------------------------------

/// يعالج عناصر «المواضيع» لتسجيل واحد.
///
/// [topics] هي `analysis.topics` كما هي — مصفوفة نصوص.
export async function linkTopics(uid, recordingId, topics) {
  const items = buildTopicItems(recordingId, topics);
  if (items.length === 0) return { created: 0, suggested: 0, skipped: true };

  if (!embeddingsConfigured()) {
    // مو خطأ: المفتاح غير مضبوط عمدًا لين يقرّر صاحب المشروع تفعيل المزوّد.
    console.log(
      `[${recordingId}] ربط المواضيع متوقّف: ما فيه OPENAI_API_KEY بالبيئة.`,
    );
    return { created: 0, suggested: 0, skipped: true };
  }

  const vectors = await embedTexts(items.map((i) => i.text));
  if (!vectors || vectors.length !== items.length) {
    throw new Error('عدد المتجهات ما يطابق عدد عناصر المواضيع.');
  }

  // المرشّحون = مواضيع المستخدم القائمة. نضيف لها كل موضوع ننشئه بهذي الجولة
  // عشان عنصران متشابهان بنفس التسجيل ما ينتجان موضوعين مكرّرين.
  const candidates = await listTopics(uid);

  const links = [];
  let created = 0;
  let suggested = 0;

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const vector = vectors[i];
    const decision = decideForItem(vector, candidates);

    if (decision.action === 'create') {
      const topic = await createTopic(uid, {
        label: item.text,
        embedding: vector,
        recordingId,
        categoryItemId: item.itemId,
      });
      candidates.push(topic);
      created++;

      links.push({
        itemId: item.itemId,
        text: item.text,
        linkedTopicId: topic.id,
        topicSuggestion: null,
      });
    } else {
      // مرشّح فوق العتبة → اقتراح معلّق، بلا ربط تلقائي.
      suggested++;
      links.push({
        itemId: item.itemId,
        text: item.text,
        linkedTopicId: null,
        topicSuggestion: {
          suggestedTopicId: decision.topicId,
          suggestedLabel: decision.label,
          // نخزّن الدرجة عشان ضبط العتبة لاحقًا يصير على بيانات حقيقية
          // بدل تخمين ثانٍ.
          score: Number(decision.score.toFixed(4)),
          status: 'pending',
        },
      });
    }
  }

  await saveTopicLinks(uid, recordingId, links);
  return { created, suggested, skipped: false };
}

/// غلاف لا يرمي أبدًا — هذا ما يُستدعى من خط المعالجة.
export async function linkTopicsInBackground(uid, recordingId, analysis) {
  try {
    const result = await linkTopics(uid, recordingId, analysis?.topics ?? []);
    if (!result.skipped) {
      console.log(
        `[${recordingId}] المواضيع: ${result.created} جديد، ${result.suggested} مقترح.`,
      );
    }
  } catch (err) {
    // نبتلع عمدًا: التحليل محفوظ، والتسجيل مكتمل. غياب موضوع أهون بكثير من
    // كسر حفظ نجح فعلًا.
    console.error(`[${recordingId}] تعذّر ربط المواضيع (متجاهَل):`, err.message);
  }
}
