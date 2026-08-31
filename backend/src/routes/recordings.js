import { Router } from 'express';
import multer from 'multer';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { uploadRateLimit } from '../middleware/uploadRateLimit.js';
import { verifyToken } from '../middleware/verifyToken.js';
import { transcribe } from '../services/transcription.js';
import { analyze } from '../services/analysis.js';
import { linkTopicsInBackground } from '../services/topics.js';
import {
  hasStoredTranscript,
  markAnalyzing,
  markTranscribing,
  markTranscriptionFailed,
  saveAnalysis,
  saveTranscript,
} from '../services/transcriptStore.js';

// ---------------------------------------------------------------------------
// السيرفر بلا حالة (stateless) افتراضيًا.
//
// أي استضافة مجانية حقيقية قرصها مؤقت: يُمسح مع كل إعادة نشر أو إعادة
// تشغيل أو دخول سبات. فما نعتمد على بقاء الملف إطلاقًا.
//
// وهذا مو تنازلًا: **الجوال هو مصدر الحقيقة للصوت أصلًا** (DraftStore
// محلي يشتغل بدون إنترنت). السيرفر يحتاج الصوت للحظة المعالجة فقط:
// يستقبل ← يفرّغ ← يحلّل ← يكتب Firestore ← يرمي الملف.
//
// `KEEP_AUDIO=1` للتطوير المحلي فقط: يبقي الصوت و<id>.json على القرص
// عشان نقدر نعيد تشغيل الخط على تسجيل موجود بدون الجوال. مطفي افتراضيًا
// عمدًا حتى يكون سلوك التطوير مطابقًا للإنتاج ما لم نطلب العكس صراحةً.
// ---------------------------------------------------------------------------
const KEEP_AUDIO = process.env.KEEP_AUDIO === '1';

const STORAGE_ROOT =
  process.env.STORAGE_ROOT ||
  (KEEP_AUDIO
    ? path.join(process.cwd(), 'storage')
    : path.join(os.tmpdir(), 'mindrop-uploads'));

// معرّف التسجيل يدخل مباشرة بمسار ملف على القرص، فلازم نتأكد إنه أحرف/أرقام/
// شرطة بس. أي شي غير كذا (زي ../) نرفضه عشان نمنع الوصول لمسار خارج مجلد
// storage (path traversal) — نفس فكرة uuid الحقيقي أصلًا.
const SAFE_ID = /^[a-zA-Z0-9_-]+$/;

const storage = multer.diskStorage({
  destination: (req, _file, cb) => {
    // req.uid يجي من verifyToken (توكن Firebase متحقق منه فعليًا) — مو من
    // الرابط. من هذي الخطوة ما فيه طريقة أحد يرفع باسم uid غير حسابه.
    const dir = path.join(STORAGE_ROOT, req.uid);
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, _file, cb) => {
    cb(null, `${req.params.recordingId}.m4a`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 25 * 1024 * 1024 }, // 25MB كافي جدًا لتسجيل صوتي عادي
});

function validateRecordingId(req, res, next) {
  if (!SAFE_ID.test(req.params.recordingId)) {
    return res.status(400).json({ error: 'recordingId فيه أحرف غير مسموحة' });
  }
  next();
}

/// يفرّغ التسجيل ويخزّن النتيجة بجنب ملف الصوت (<id>.json).
///
/// يشتغل **بعد** ما نرد على الجوال عمدًا: التفريغ ياخذ ثوانٍ، وما فيه سبب
/// يخلي الجوال ينتظره — الرفع نجح فعلًا بمجرد وصول الملف للقرص.
///
/// ولو فيه تفريغ سابق لنفس التسجيل، نتخطاه: إعادة رفع نفس الملف ما تعيد
/// الدفع لنفس النتيجة.
/// **عقد هذي الدالة: لا ترفض أبدًا.**
///
/// تُنادى بلا `await` بعد ما رجع الرد للجوال، فما فيه أحد ينتظرها ولا أحد
/// يلتقط رفضها. ومنذ Node 15 السلوك الافتراضي للرفض غير الملتقط هو **إنهاء
/// العملية**، يعني خطأ بمعالجة تسجيل واحد يسقط السيرفر لكل المستخدمين.
///
/// الطبقات الداخلية (`processRecording` و`analyzeInBackground` و`bestEffort`)
/// تلتقط أخطاءها المتوقعة أصلًا، فهذا حزام أمان لغير المتوقع: رمية متزامنة
/// قبل أول `await`، أو مسار جديد يضيفه أحد لاحقًا وينسى حراسته. الطبقة
/// الخارجية أرخص من الاعتماد على أن كل طبقة داخلية ستبقى محروسة للأبد.
async function transcribeInBackground(audioPath, recordingId, uid) {
  try {
    await processRecording(audioPath, recordingId, uid);
  } catch (err) {
    // ما نعيد الرمي: ما فيه مستدعٍ يلتقط، وإعادة الرمي هي بالضبط الشي
    // اللي نمنعه هنا.
    console.error(`[${recordingId}] خطأ غير متوقع بالمعالجة:`, err);
  } finally {
    try {
      // يمشي على كل المسارات — نجاح، فشل، أو تخطّي — فما يتراكم أي صوت على
      // القرص المؤقت. الجوال يحتفظ بالنسخة الدائمة.
      await discardAudio(audioPath, recordingId);
    } catch (err) {
      // `discardAudio` تلتقط أخطاءها بنفسها، لكن رمية من `finally` تتغلّب
      // على كل ما سبقها وتهرب من الـ`catch` اللي فوق — فتُحرس هنا أيضًا.
      console.error(`[${recordingId}] تعذّر تنظيف الصوت المؤقت:`, err);
    }
  }
}

/// يحذف الصوت بعد انتهاء المعالجة. يُتخطّى بالتطوير لما KEEP_AUDIO=1.
async function discardAudio(audioPath, recordingId) {
  if (KEEP_AUDIO) return;
  try {
    await fsp.unlink(audioPath);
  } catch (err) {
    if (err.code !== 'ENOENT') {
      console.error(`[${recordingId}] تعذّر حذف الصوت المؤقت:`, err.message);
    }
  }
}

async function processRecording(audioPath, recordingId, uid) {
  const transcriptPath = audioPath.replace(/\.m4a$/, '.json');

  try {
    // فحص التكرار من Firestore لا من القرص.
    //
    // كان يفحص وجود <id>.json محليًا، وهذا ينكسر بصمت مع قرص مؤقت: بعد أي
    // إعادة نشر يختفي الملف، فإعادة رفع نفس التسجيل تعيد التفريغ والتحليل
    // وتدفع مرتين على نفس النتيجة. Firestore يبقى بعد إعادة النشر، فهو
    // المكان الصحيح لهذا السؤال.
    if (await hasStoredTranscript(uid, recordingId)) {
      console.log(`[${recordingId}] فيه تفريغ سابق بـ Firestore — تخطّي.`);
      return;
    }
  } catch (err) {
    // ما قدرنا نتأكد؟ نكمل. إعادة تفريغ أرخص من فقدان النتيجة كليًا.
    console.error(`[${recordingId}] تعذّر فحص التفريغ السابق:`, err.message);
  }

  try {
    console.log(`[${recordingId}] جارِ التفريغ...`);
    // حالة حقيقية مو تجميلية: من هنا لين تخلص، التسجيل فعلًا تحت التفريغ.
    // نكتبها قبل النداء عشان يشوفها المستخدم بالتطبيق أثناء الانتظار.
    //
    // best-effort: لو Firestore طاح، ما نوقف التفريغ عشانه. النص هو القيمة
    // الحقيقية، وحالة وسيطة تجميلية ما تستاهل تعطّله.
    await bestEffort(() => markTranscribing(uid, recordingId));

    const { text, costUsd } = await transcribe(audioPath);

    // نسخة القرص للتطوير فقط — بالإنتاج Firestore هو المخزن الوحيد.
    if (KEEP_AUDIO) {
      await fsp.writeFile(
        transcriptPath,
        JSON.stringify(
          { recordingId, text, costUsd, at: new Date().toISOString() },
          null,
          2,
        ),
      );
    }
    await bestEffort(() => saveTranscript(uid, recordingId, { text, costUsd }));

    console.log(`[${recordingId}] تم التفريغ (تكلفة: ${costUsd ?? 'غير معروفة'}$):`);
    console.log(text);

    await analyzeInBackground(text, recordingId, uid);
  } catch (err) {
    // الفشل هنا ما يلغي نجاح الرفع — الصوت محفوظ، والتفريغ يقدر يُعاد لاحقًا.
    //
    // مهم: نصل هنا أيضًا لما يرفض حارس الهلوسة الناتج. وقتها ما يُكتب ملف
    // <id>.json ولا حقل transcript بـ Firestore — الرفض ما ينتج نصًا أبدًا،
    // لا على القرص ولا بالسحابة.
    console.error(`[${recordingId}] فشل التفريغ:`, err.message);
    await bestEffort(() => markTranscriptionFailed(uid, recordingId, err.message));
  }
}

/// يحلّل النص المفرَّغ إلى محتوى منظّم ويخزّنه، ويضع `completed` عند
/// النجاح فقط.
///
/// **الفشل هنا لا يمس النص ولا الصوت إطلاقًا**: التفريغ محفوظ على القرص
/// وبـ Firestore قبل ما نصل لهنا، والتحليل طبقة فوقه. لو طاح، نسجّل
/// السبب ونخلي النص معروضًا للمستخدم كما هو.
///
/// نضع `failed` عند فشل التحليل عمدًا بدل ما نترك `analyzing` معلّقة:
/// حالة "جارِ التحليل" الأبدية تكذب على المستخدم. النص نفسه يظهر بأي
/// حال — عرضه مربوط بوجود `transcript` لا بالحالة.
async function analyzeInBackground(transcript, recordingId, uid) {
  try {
    console.log(`[${recordingId}] جارِ التحليل...`);
    await bestEffort(() => markAnalyzing(uid, recordingId));

    const analysis = await analyze(transcript);

    await bestEffort(() => saveAnalysis(uid, recordingId, analysis));
    console.log(`[${recordingId}] تم التحليل:`, JSON.stringify(analysis));

    // ربط المواضيع الدائمة — **بعد** ما اكتمل التحليل وصار `completed`.
    //
    // موضعه هنا مقصود: الحالة النهائية مكتوبة قبله، فحتى لو تعطّل هذا كليًا
    // يبقى التسجيل مكتملًا وظاهرًا للمستخدم كما هو. والدالة نفسها ما ترمي
    // أبدًا، فما تحتاج `bestEffort` — تبتلع فشلها بداخلها.
    await linkTopicsInBackground(uid, recordingId, analysis);
  } catch (err) {
    console.error(`[${recordingId}] فشل التحليل:`, err.message);
    await bestEffort(() =>
      markTranscriptionFailed(uid, recordingId, `فشل التحليل: ${err.message}`),
    );
  }
}

/// ينفّذ كتابة سحابية بدون ما يسمح لفشلها يوقف خط المعالجة.
async function bestEffort(fn) {
  try {
    await fn();
  } catch (err) {
    console.error('  تعذّرت كتابة Firestore (متجاهَلة):', err.message);
  }
}

const router = Router();

// ترتيب السلسلة مقصود بالكامل:
//   verifyToken      يحدد req.uid قبل أي شي — بلا توكن صالح نرجع 401 وما
//                    نوصل حتى لمرحلة الملف.
//   uploadRateLimit  بعده مباشرة لأنه **يحتاج req.uid** مفتاحًا، وقبل
//                    multer عمدًا: الرفض بعد multer يعني إننا استقبلنا
//                    الحمولة وكتبناها على القرص ثم رميناها — ندفع النطاق
//                    والـI/O مقابل طلب رفضناه أصلًا.
//   validateRecordingId ثم multer.
router.post(
  '/recordings/:recordingId',
  verifyToken,
  uploadRateLimit,
  validateRecordingId,
  upload.single('audio'),
  (req, res) => {
    if (!req.file) {
      return res.status(400).json({ error: 'ما وصل ملف صوت (الحقل audio)' });
    }

    res.json({
      ok: true,
      uid: req.uid,
      recordingId: req.params.recordingId,
      bytes: req.file.size,
    });

    // بعد الرد — بدون await عمدًا (راجع تعليق الدالة).
    // uid يجي من verifyToken، فالكتابة بـ Firestore تروح لمستند صاحبه فعلًا.
    //
    // `.catch()` هنا زائد عن الحاجة بحكم أن الدالة نفسها ما ترفض — وهذا
    // مقصود: حارسان مستقلان أرخص من الاعتماد على أن أحدهما ما ينكسر بتعديل
    // لاحق. ولو انكسر العقد، هذا السطر يمنع سقوط العملية.
    transcribeInBackground(req.file.path, req.params.recordingId, req.uid).catch(
      (err) => console.error(`[${req.params.recordingId}] رفض غير متوقع:`, err),
    );
  },
);

export default router;
