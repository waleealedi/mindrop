import { getFirestore } from 'firebase-admin/firestore';

// استيراد جانبي مقصود: firebaseAdmin.js ينفّذ initializeApp عند تحميله.
import '../firebaseAdmin.js';

// ---------------------------------------------------------------------------
// تخزين المواضيع الدائمة (العابرة للتسجيلات).
//
//   users/{uid}/topics/{topicId}
//
// **إضافي بالكامل.** ما فيه حقل واحد قائم يتغيّر شكله: العناصر الأربعة
// (مهام/أهداف/أفكار/مواضيع) تبقى كما هي حرفيًا، وكل ما يخص هذي الميزة يعيش
// إما بمجموعة جديدة أو بحقل جديد بمستند التسجيل.
//
// Admin SDK يتجاوز قواعد Firestore، فالباك-إند يكتب هنا بلا حاجة لقاعدة.
// القاعدة المضافة بـ firestore.rules للعميل وحده (جولة الواجهة لاحقًا).
// ---------------------------------------------------------------------------

const db = getFirestore();

function topicsRef(uid) {
  return db.collection('users').doc(uid).collection('topics');
}

function recordingRef(uid, recordingId) {
  return db.collection('users').doc(uid).collection('recordings').doc(recordingId);
}

/// كل مواضيع المستخدم مع متجهاتها — مرشّحو المطابقة.
export async function listTopics(uid) {
  const snap = await topicsRef(uid).get();
  return snap.docs.map((d) => {
    const data = d.data() ?? {};
    return {
      id: d.id,
      label: data.label ?? '',
      embedding: Array.isArray(data.embedding) ? data.embedding : [],
      itemCount: typeof data.itemCount === 'number' ? data.itemCount : 0,
    };
  });
}

/// ينشئ موضوعًا جديدًا من عنصر واحد ويرجّع شكله الجاهز للمطابقة.
export async function createTopic(uid, { label, embedding, recordingId, categoryItemId }) {
  const now = new Date().toISOString();
  const ref = topicsRef(uid).doc();

  await ref.set({
    label,
    createdAt: now,
    lastActivityAt: now,
    // مؤشّرات فقط — ما ننسخ نص العنصر هنا. مصدره الوحيد يبقى تحليل التسجيل،
    // فما يصير عندنا نسختان تتفارقان.
    itemRefs: [{ recordingId, categoryItemId }],
    embedding,
    itemCount: 1,
  });

  return { id: ref.id, label, embedding, itemCount: 1 };
}

/// يكتب روابط/اقتراحات المواضيع لتسجيل واحد.
///
/// **ليش حقل موازٍ (`topicLinks`) بدل تعديل عناصر `analysis.topics`:**
/// العناصر اليوم **نصوص عارية**، وعميل Flutter يقرأها بـ
/// `whereType<String>()`. تحويلها لكائنات عشان نضيف `linkedTopicId` داخلها
/// كان يخلي العميل **يسقط كل عنصر بصمت** — المواضيع تختفي من شاشة الاستماع
/// ومن الخريطة بلا أي خطأ ظاهر. حقل جديد بمستوى المستند يتجاهله العميل
/// الحالي تمامًا، وتقرأه جولة الواجهة القادمة بلا أي تغيير مخطط.
export async function saveTopicLinks(uid, recordingId, links) {
  await recordingRef(uid, recordingId).set(
    { topicLinks: links, topicLinksAt: new Date().toISOString() },
    { merge: true },
  );
}
