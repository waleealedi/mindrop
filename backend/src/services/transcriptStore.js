import { getFirestore } from 'firebase-admin/firestore';

// استيراد جانبي مقصود: firebaseAdmin.js ينفّذ initializeApp عند تحميله،
// و getFirestore() ما يشتغل قبلها. ما نلمس ذاك الملف — نستفيد من أثره فقط.
import '../firebaseAdmin.js';

// ---------------------------------------------------------------------------
// كتابة حالة التفريغ ونصّه إلى نفس مستند التسجيل اللي ينشئه التطبيق:
//   users/{uid}/recordings/{recordingId}
//
// التطبيق يكتب هناك metadata محلية (تاريخ/مدة/حالة)، والباك-إند يكتب
// النتيجة. نستخدم merge دائمًا عشان ما نمسح حقول الطرف الثاني.
//
// Admin SDK يتجاوز قواعد Firestore (يشتغل بصلاحية حساب الخدمة)، فالقواعد
// اللي تقصر المستند على صاحبه تبقى فعّالة على التطبيق وحده — وهذا المطلوب.
// ---------------------------------------------------------------------------

const db = getFirestore();

function docRef(uid, recordingId) {
  return db.collection('users').doc(uid).collection('recordings').doc(recordingId);
}

/// هل عند هذا التسجيل تفريغ مخزَّن أصلًا؟
///
/// هذا هو فحص عدم التكرار بعد ما صار السيرفر بلا قرص دائم: Firestore يبقى
/// بعد إعادة النشر، بينما ملف <id>.json ما يبقى.
export async function hasStoredTranscript(uid, recordingId) {
  const snap = await docRef(uid, recordingId).get();
  if (!snap.exists) return false;
  const transcript = snap.data()?.transcript;
  return typeof transcript === 'string' && transcript.trim().length > 0;
}

/// حالة وسيطة حقيقية: الصوت وصل والتفريغ بدأ فعلًا.
export async function markTranscribing(uid, recordingId) {
  await docRef(uid, recordingId).set(
    { status: 'transcribing', updatedAt: new Date().toISOString() },
    { merge: true },
  );
}

/// يخزّن النص. **ما يضع `completed`**: التفريغ نصف الخط فقط، والاكتمال
/// يجي بعد التحليل (انظر [saveAnalysis]).
export async function saveTranscript(uid, recordingId, { text, costUsd }) {
  await docRef(uid, recordingId).set(
    {
      transcript: text,
      transcriptCostUsd: costUsd,
      transcribedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      // ننظّف أي خطأ قديم: نجاح المحاولة الحالية يلغي فشل السابقة.
      errorMessage: null,
    },
    { merge: true },
  );
}

/// حالة وسيطة حقيقية: التفريغ خلص والتحليل بدأ فعلًا.
export async function markAnalyzing(uid, recordingId) {
  await docRef(uid, recordingId).set(
    { status: 'analyzing', updatedAt: new Date().toISOString() },
    { merge: true },
  );
}

/// نهاية الخط: المحتوى المنظّم جاهز.
export async function saveAnalysis(uid, recordingId, analysis) {
  const ref = docRef(uid, recordingId);

  // العنوان اللي عدّله المستخدم بيده يفوز على أي عنوان يولّده الموديل.
  //
  // **ليش يحتاج حماية أصلًا وما فيه مسار إعادة تحليل صريح:** `analysis`
  // خريطة متداخلة، و`merge: true` يستبدلها كاملة لا يدمج داخلها. فأي مرور
  // ثانٍ على نفس التسجيل يمسح `analysis.title`. والمرور الثاني ممكن فعلًا:
  // تسجيل فشل تفريغه (أو فشلت كتابة النص بـ Firestore) يعيده الطابور،
  // و`hasStoredTranscript` وقتها ترجّع false فيمشي الخط كامل من جديد.
  //
  // نقرأ قبل الكتابة عمدًا رغم إنها قراءة إضافية: تصير مرة وحدة بعمر
  // التسجيل، وثمنها لا شيء مقابل مسح تسمية كتبها المستخدم بنفسه.
  let finalAnalysis = analysis;
  try {
    const snap = await ref.get();
    const data = snap.exists ? snap.data() : null;
    const existingTitle = data?.analysis?.title;
    if (
      data?.titleEditedByUser === true &&
      typeof existingTitle === 'string' &&
      existingTitle.trim().length > 0
    ) {
      finalAnalysis = { ...analysis, title: existingTitle };
    }
  } catch (err) {
    // ما قدرنا نقرأ؟ نكمل بعنوان الموديل. فقدان تسمية يدوية أسوأ من
    // فقدان التحليل كله، لكن إيقاف التحليل عشان قراءة فاشلة أسوأ منهما.
    console.error(`[${recordingId}] تعذّر فحص العنوان اليدوي:`, err.message);
  }

  await ref.set(
    {
      analysis: finalAnalysis,
      status: 'completed',
      analyzedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
}

/// فشل التفريغ (أو رفضه حارس الهلوسة) — نسجّل السبب وما نكتب أي نص.
export async function markTranscriptionFailed(uid, recordingId, reason) {
  await docRef(uid, recordingId).set(
    {
      status: 'failed',
      errorMessage: reason,
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
}
