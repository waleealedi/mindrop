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

  // نسخ التسمية اليدوية داخل `analysis` عشان النسختان ما تتناقضان.
  //
  // **الحماية الحقيقية بنيوية لا هنا:** التسمية اليدوية تسكن حقل `title`
  // أعلى المستند، والعميل ما يكتب داخل `analysis` أبدًا. فإعادة التحليل
  // تكتب `analysis.title` وحدها وما تقدر تمس التسمية اليدوية إطلاقًا.
  //
  // (تصحيح لملاحظة سابقة: `merge: true` بـ Firestore يدمج الخرائط
  // المتداخلة تكراريًا، ما يستبدلها كاملة. لكن `analysis` القادمة من
  // الموديل تحمل `title` دائمًا، فبدون هذا النسخ يبقى بالمستند عنوانان
  // مختلفان — اليدوي فوق والمولَّد بالداخل.)
  //
  // القراءة تصير مرة وحدة بعمر التسجيل، فثمنها لا شيء.
  let finalAnalysis = analysis;
  try {
    const snap = await ref.get();
    const data = snap.exists ? snap.data() : null;
    const manualTitle = data?.title;
    if (
      data?.titleEditedByUser === true &&
      typeof manualTitle === 'string' &&
      manualTitle.trim().length > 0
    ) {
      finalAnalysis = { ...analysis, title: manualTitle.trim() };
    }
  } catch (err) {
    // ما قدرنا نقرأ؟ نكمل بعنوان الموديل. التسمية اليدوية بأمان بأي حال
    // لأنها بحقل ثاني — أسوأ نتيجة هنا تناقض داخلي ما يشوفه المستخدم.
    console.error(`[${recordingId}] تعذّر فحص التسمية اليدوية:`, err.message);
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
