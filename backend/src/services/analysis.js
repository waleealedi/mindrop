// ---------------------------------------------------------------------------
// تحويل الفكرة المنطوقة (بعد تفريغها) إلى محتوى منظّم.
//
// **اختيار الموديل — مبني على تجربة حيّة، مو على سمعة.** جرّبنا مرشّحي
// Groq الثلاثة على نفس النص العربي المخلوط وبنفس المخطط الصارم:
//
//   openai/gpt-oss-120b   نجح على الحالتين، وحافظ على لغة المتحدث حرفيًا
//   qwen/qwen3.6-27b      HTTP 400 json_validate_failed على النص الحقيقي
//   allam-2-7b            HTTP 400: لا يدعم response_format=json_schema أصلًا
//
// اللافت إن allam-2-7b هو الموديل المتخصص بالعربية، ومع ذلك يسقط: الإخراج
// المنظّم المتحقَّق منه شرط أساسي عندنا، وهو ما يدعمه. وqwen فشل تحديدًا
// على المدخل اللي نحتاجه. فالاختيار انحسم بالأدلة.
//
// حدود الطبقة المجانية للموديل المختار (من ترويسات الرد الحيّة):
// 1000 طلب/يوم و8000 توكن/دقيقة — أكثر من كافي لتحليل واحد لكل تسجيل.
// ---------------------------------------------------------------------------

const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
const ANALYSIS_MODEL = 'openai/gpt-oss-120b';

/// المخطط مقصود بساطته: أربعة حقول، كلها مصفوفات نصوص.
///
/// **ليش نصوص بسيطة مو كائنات فيها حقول إضافية** (أولوية، تاريخ استحقاق،
/// إلخ): كل حقل اختياري زائد هو دعوة مفتوحة للموديل يخترع قيمة ما قالها
/// المتحدث. أسوأ فشل ممكن بهذي الميزة إنها تضيف "مهمة" ما قالها المستخدم،
/// فنقلّل مساحة الاختراع للحد الأدنى: نص المهمة كما نُطق، وبس.
///
/// `strict: true` مع `additionalProperties: false` يخلي Groq يرفض أي ناتج
/// خارج الشكل بدل ما يمرّره لنا.
const EXTRACTION_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['tasks', 'goals', 'ideas', 'topics'],
  properties: {
    tasks: { type: 'array', items: { type: 'string' } },
    goals: { type: 'array', items: { type: 'string' } },
    ideas: { type: 'array', items: { type: 'string' } },
    topics: { type: 'array', items: { type: 'string' } },
  },
};

/// التعليمات مكتوبة بالإنجليزية عمدًا (لغة تعليمات، مو لغة إخراج) بينما
/// القاعدة الأولى تفرض أن يكون **الإخراج** بلغة المتحدث نفسها.
const SYSTEM_PROMPT = [
  'You extract structure from a spoken thought that has already been transcribed.',
  '',
  'RULES:',
  '1. Write every output value in the SAME language as the transcript. If the transcript is Arabic, write Arabic. Never translate.',
  '2. If the transcript mixes Arabic and English, keep each term in the language the speaker used.',
  '3. Extract ONLY what the speaker actually said. Never invent, infer, or complete a thought.',
  '4. Empty arrays are correct and expected for a short recording. Do not pad.',
  '',
  'tasks   = concrete actions the speaker intends to do',
  'goals   = outcomes they want, without a concrete action',
  'ideas   = thoughts/observations that are neither task nor goal',
  'topics  = 1-3 word subject tags for grouping',
].join('\n');

/// يحلّل نص التفريغ ويرجّع محتوى منظّمًا متحقَّقًا من شكله.
/// يرمي عند أي فشل — المستدعي يتعامل معه كـ best-effort.
export async function analyze(transcript) {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    throw new Error('ناقص GROQ_API_KEY بملف .env — التحليل ما يشتغل بدونه.');
  }

  const response = await fetch(GROQ_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: ANALYSIS_MODEL,
      // صفر: نبي نفس المخرج لنفس النص، وأقل ميل ممكن للتأليف.
      temperature: 0,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: transcript },
      ],
      response_format: {
        type: 'json_schema',
        json_schema: { name: 'extraction', strict: true, schema: EXTRACTION_SCHEMA },
      },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Groq رفض طلب التحليل (${response.status}): ${body}`);
  }

  const content = (await response.json()).choices?.[0]?.message?.content;
  if (typeof content !== 'string') {
    throw new Error('رد تحليل غير متوقع من Groq: ما فيه message.content');
  }

  let parsed;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error(`ناتج التحليل مو JSON صالح: ${content.slice(0, 200)}`);
  }

  return validateExtraction(parsed);
}

/// تحقّق دفاعي بعد الحزمة: نمر بـ `strict` من Groq، لكن ما نثق بالمزوّد
/// وحده. أي انحراف عن الشكل يرمي بصوت عالٍ بدل ما يُخزَّن ناتج مشوّه.
function validateExtraction(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('ناتج التحليل لازم يكون كائن JSON.');
  }

  const out = {};
  for (const key of ['tasks', 'goals', 'ideas', 'topics']) {
    const list = value[key];
    if (!Array.isArray(list)) {
      throw new Error(`ناتج التحليل: الحقل "${key}" لازم يكون مصفوفة.`);
    }
    for (const item of list) {
      if (typeof item !== 'string') {
        throw new Error(`ناتج التحليل: كل عنصر بـ "${key}" لازم يكون نصًا.`);
      }
    }
    // نشيل الفراغات والعناصر الفاضية — مصفوفة فاضية نتيجة صحيحة تمامًا.
    out[key] = list.map((s) => s.trim()).filter((s) => s.length > 0);
  }

  return out;
}
