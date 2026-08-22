import fs from 'node:fs/promises';
import path from 'node:path';

// ---------------------------------------------------------------------------
// تفريغ الصوت إلى نص.
//
// المزوّد الفعّال حاليًا: Groq (Whisper large v3 turbo).
// السبب: طبقة مجانية حقيقية بدون بطاقة ائتمان. المزوّد السابق (OpenRouter +
// Qwen3 ASR) اشتغل من ناحية الكود بالكامل — المفتاح صالح وشكل الطلب متحقَّق
// منه — لكنه يفرض حدًا أدنى **$0.50 رصيد** لأي طلب صوتي، فرجع 402 قبل ما
// يوصل للموديل. يعني التوقّف كان سبب فوترة بحت، مو عيب برمجي.
// انظر transcribeViaOpenRouter() بالأسفل: محفوظة وجاهزة للرجوع لها.
//
// ليش كنا اخترنا Qwen أصلًا (المنطق لسا صالح لو رجعنا له): يدعم العربي
// صراحةً مع كشف تلقائي للغة داخل نفس المقطع — وهذا بالضبط سلوك مستخدم
// Mindrop (يخلط عربي/إنجليزي بنفس الجملة).
//
// ليش OpenRouter كان مفضّلًا على Alibaba Cloud مباشرة: التسجيل عند Alibaba
// يتطلب اختيار منطقة + workspace ID + مفاتيح غير متبادلة بين المناطق.
// OpenRouter مفتاح واحد وواجهة متوافقة مع OpenAI، وبنفس السعر تقريبًا.
// ---------------------------------------------------------------------------

const GROQ_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';
const GROQ_MODEL = 'whisper-large-v3-turbo';

// ---------------------------------------------------------------------------
// حارس الهلوسة — عتبات مشتقة من التسجيلات السبعة الفعلية، مو منقولة من مقال.
//
// Whisper يخترع نصًا من الصمت أو الضجيج بدل ما يرجّع فراغ. عندنا حالتان
// موثّقتان: مقطع 5 ثوانٍ رجع كوري (" 야, 디디..."), وآخر رجع نقطة وحدة.
// لو مرّت هذي كأفكار حقيقية، المستخدم يلقى بقائمته "أفكارًا" ما قالها أبدًا.
//
// الأرقام الفعلية من verbose_json (whisper-large-v3-turbo):
//
//   ملف                  حكم        max_no_speech   mean_avg_logprob   language
//   527608e1 (ar 33s)    سليم         0.0000           -0.2421          Arabic
//   2c944c82 (ar 20s)    سليم         0.0000           -0.2763          Arabic
//   bd36bce3 (en 8s)     سليم         0.0000           -0.4068          English
//   39f7951b (ar 6s)     سليم         0.0000           -0.1219          Arabic
//   8761b834 (mix 27s)   سليم         0.0000           -0.3430          Arabic
//   a8392227 (كوري)      فاشل         0.0000           -0.4091          Korean
//   a3177485 (نقطة)      فاشل         0.0000           -1.4866          English
//
// ثلاث خلاصات غيّرت التصميم:
//
// 1) `no_speech_prob` = 0.0000 بكل السبعة — بما فيها الفاشلين. ما يفرّق ولا
//    شي مع هذا الموديل. نبقيه كشبكة أمان لصمت حقيقي (0.9) مع التنويه إنه
//    ما اشتغل ولا مرة على عيّناتنا.
//
// 2) `avg_logprob` يفرز حالة النقطة بوضوح (-1.4866 مقابل أسوأ سليم
//    -0.4068) لكنه **يفشل تمامًا** مع الكوري: -0.4091 مقابل -0.4068 للمقطع
//    الإنجليزي السليم — فرق 0.0023. أي عتبة تمسك الكوري ترمي نصف السليم.
//
// 3) نستخدم **متوسط** avg_logprob مو أدناه: بملف 527608e1 السليم فيه مقطع
//    واحد بـ -1.2676 (كلمة أخيرة قصيرة)، فقاعدة مبنية على الأدنى ترفض
//    تسجيلًا صحيحًا.
//
// لأن الكوري ما ينفرز رقميًا، السيجنال الوحيد اللي يمسكه هو اللغة
// المكتشَفة نفسها. هذا **افتراض منتج** صريح: مستخدم Mindrop يتكلم عربي
// و/أو إنجليزي. لو توسّعنا للغات ثانية، وسّع القائمة هنا.
// ملاحظة: ما زلنا **لا** نمرّر `language` للموديل — الكشف التلقائي يشتغل
// كامل، إحنا فقط ما نثق بنتيجة خارج نطاق مستخدمينا.
// ---------------------------------------------------------------------------
const MIN_MEAN_AVG_LOGPROB = -1.0;
const MAX_NO_SPEECH_PROB = 0.9;
const ALLOWED_LANGUAGES = new Set(['arabic', 'english']);

/// نتجاهل تمرير `language` عمدًا: تحديد لغة ثابتة يلغي الكشف التلقائي،
/// وهو أهم ميزة نبيها هنا (مقطع فيه عربي وإنجليزي مع بعض).
export async function transcribe(audioPath) {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    throw new Error(
      'ناقص GROQ_API_KEY بملف .env — التفريغ ما يشتغل بدونه (راجع .env.example).',
    );
  }

  const buffer = await fs.readFile(audioPath);

  // Groq يتبع واجهة OpenAI: multipart/form-data وفيه حقل `file`، مو JSON
  // بـ base64 مثل OpenRouter. الاسم مهم — منه يعرف الامتداد (m4a).
  const form = new FormData();
  form.append('file', new Blob([buffer]), path.basename(audioPath));
  form.append('model', GROQ_MODEL);
  // verbose_json يرجّع segments مع no_speech_prob و avg_logprob واللغة
  // المكتشَفة — بدونها ما عندنا أي أساس نحكم فيه على جودة الناتج.
  form.append('response_format', 'verbose_json');

  const response = await fetch(GROQ_URL, {
    method: 'POST',
    // ما نحدد Content-Type يدويًا: fetch يضيفه مع boundary الصحيح تلقائيًا.
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Groq رفض الطلب (${response.status}): ${body}`);
  }

  const data = await response.json();
  if (typeof data.text !== 'string') {
    throw new Error(`رد غير متوقع من Groq: ${JSON.stringify(data)}`);
  }

  assertTrustworthy(data);

  return {
    text: data.text,
    // الطبقة المجانية بـ Groq ما ترجّع تكلفة بالرد إطلاقًا، والاستهلاك محسوب
    // بحدود طلبات/ثواني صوت مو بالدولار. نرجّع null بدل ما نخترع رقمًا.
    costUsd: null,
  };
}

/// يرمي خطأ لو الناتج ما يستاهل الثقة.
///
/// نرمي بدل ما نرجّع علامة: [transcribeInBackground] بـ recordings.js يمسك
/// الاستثناء ويسجّله وما يكتب ملف <id>.json إطلاقًا — وهذا بالضبط المطلوب
/// (الصوت المرفوض ما ينتج تفريغًا). فما احتجنا نغيّر recordings.js ولا عقد
/// transcribe() الخارجي.
function assertTrustworthy(data) {
  const segments = Array.isArray(data.segments) ? data.segments : [];

  // نص فاضي أو علامات ترقيم بس (حالة " ." المعروفة).
  const meaningful = data.text.replace(/[\p{P}\p{S}\p{Z}\s]/gu, '');
  if (meaningful.length === 0) {
    throw new Error('تفريغ مرفوض: النص فاضي أو علامات ترقيم فقط.');
  }

  const language = String(data.language ?? '').toLowerCase();
  if (language && !ALLOWED_LANGUAGES.has(language)) {
    throw new Error(
      `تفريغ مرفوض: اللغة المكتشَفة "${data.language}" خارج نطاق مستخدمي ` +
        'Mindrop (عربي/إنجليزي) — غالبًا هلوسة من صمت أو ضجيج.',
    );
  }

  if (segments.length === 0) return;

  const meanAvgLogprob =
    segments.reduce((sum, s) => sum + (s.avg_logprob ?? 0), 0) / segments.length;
  if (meanAvgLogprob < MIN_MEAN_AVG_LOGPROB) {
    throw new Error(
      `تفريغ مرفوض: ثقة الموديل منخفضة (mean avg_logprob ${meanAvgLogprob.toFixed(4)} ` +
        `< ${MIN_MEAN_AVG_LOGPROB}).`,
    );
  }

  const maxNoSpeech = Math.max(...segments.map((s) => s.no_speech_prob ?? 0));
  if (maxNoSpeech > MAX_NO_SPEECH_PROB) {
    throw new Error(
      `تفريغ مرفوض: المقطع غالبًا بدون كلام (no_speech_prob ${maxNoSpeech.toFixed(4)} ` +
        `> ${MAX_NO_SPEECH_PROB}).`,
    );
  }
}

// ---------------------------------------------------------------------------
// النسخة السابقة (OpenRouter + Qwen3 ASR Flash) — غير مفعّلة.
//
// موقوفة بسبب الفوترة فقط: OpenRouter يتطلب حدًا أدنى $0.50 رصيد لأي طلب
// صوتي (402)، وليس بسبب خلل بالكود. شكل الطلب أدناه متحقَّق منه مقابل
// الـ API الحي: طلب ناقص `model` أو `input_audio` يرجع 400 من المدقق، بينما
// هذا الشكل عدّى التحقق ووصل لبوابة الرصيد.
//
// للرجوع: بدّل الاستدعاء بـ recordings.js أو خلِّ transcribe() تنادي هذي.
// ---------------------------------------------------------------------------

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/audio/transcriptions';
const OPENROUTER_MODEL = 'qwen/qwen3-asr-flash-2026-02-10';

export async function transcribeViaOpenRouter(audioPath) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    throw new Error(
      'ناقص OPENROUTER_API_KEY بملف .env — التفريغ ما يشتغل بدونه (راجع .env.example).',
    );
  }

  const buffer = await fs.readFile(audioPath);
  // امتداد الملف بدون النقطة: 'm4a'. OpenRouter يدعمه مباشرة، فما نحتاج
  // نحوّل الصيغة بـ ffmpeg قبل الإرسال.
  const format = path.extname(audioPath).slice(1).toLowerCase();

  const response = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: OPENROUTER_MODEL,
      input_audio: { data: buffer.toString('base64'), format },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`OpenRouter رفض الطلب (${response.status}): ${body}`);
  }

  const data = await response.json();
  if (typeof data.text !== 'string') {
    throw new Error(`رد غير متوقع من OpenRouter: ${JSON.stringify(data)}`);
  }

  return {
    text: data.text,
    // التكلفة الفعلية للطلب بالدولار — نخزّنها عشان نقدر نراقب المصروف
    // الحقيقي بدل ما نعتمد على تقدير نظري.
    costUsd: data.usage?.cost ?? null,
  };
}
