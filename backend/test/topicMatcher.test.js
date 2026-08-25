import assert from 'node:assert/strict';
import test from 'node:test';

import {
  SIMILARITY_THRESHOLD,
  bestMatch,
  buildTopicItems,
  cosineSimilarity,
  decideForItem,
  mergedEmbedding,
  topicItemId,
} from '../src/services/topicMatcher.js';

// ---------------------------------------------------------------------------
// اختبارات منطق المطابقة وحده — بلا شبكة وبلا Firestore.
//
// المتجهات هنا مكتوبة يدويًا بدل نداء مزوّد حقيقي: القرار المطلوب اختباره هو
// «فوق العتبة أو تحتها»، وربطه بمزوّد مدفوع يخلي الاختبار بطيئًا وهشًّا
// ويعتمد على مفتاح. الوحدة تحت الاختبار هي العتبة، لا جودة التضمين.
// ---------------------------------------------------------------------------

/// متجه بزاوية معلومة عن (1,0) — يعطينا تشابهًا نعرفه بالضبط مسبقًا.
function vectorAtAngle(radians) {
  return [Math.cos(radians), Math.sin(radians)];
}

/// متجه تشابهه مع (1,0) يساوي `target` بالضبط.
function vectorWithSimilarity(target) {
  return vectorAtAngle(Math.acos(target));
}

const BASE = [1, 0];

test('cosineSimilarity: متطابق = 1، متعامد = 0، معاكس = -1', () => {
  assert.equal(cosineSimilarity(BASE, [1, 0]), 1);
  assert.equal(cosineSimilarity(BASE, [0, 1]), 0);
  assert.equal(cosineSimilarity(BASE, [-1, 0]), -1);
  // الحجم ما يهم، الاتجاه فقط.
  assert.equal(cosineSimilarity(BASE, [5, 0]), 1);
});

test('cosineSimilarity: مدخل غير صالح يرجّع 0 بدل ما يرمي', () => {
  assert.equal(cosineSimilarity(BASE, [0, 0]), 0, 'متجه صفري');
  assert.equal(cosineSimilarity(BASE, [1, 0, 0]), 0, 'طول مختلف');
  assert.equal(cosineSimilarity(BASE, []), 0, 'فاضي');
  assert.equal(cosineSimilarity(BASE, null), 0, 'null');
  assert.equal(cosineSimilarity(BASE, ['a', 'b']), 0, 'قيم غير رقمية');
});

test('decideForItem: بلا مواضيع قائمة ينشئ موضوعًا جديدًا', () => {
  const d = decideForItem(BASE, []);
  assert.equal(d.action, 'create');
});

test('decideForItem: تحت العتبة مباشرة ينشئ، فوقها مباشرة يقترح', () => {
  const justBelow = vectorWithSimilarity(SIMILARITY_THRESHOLD - 0.02);
  const justAbove = vectorWithSimilarity(SIMILARITY_THRESHOLD + 0.02);
  const topics = [{ id: 't1', label: 'Mindrop', embedding: BASE }];

  assert.equal(decideForItem(justBelow, topics).action, 'create');

  const above = decideForItem(justAbove, topics);
  assert.equal(above.action, 'suggest');
  assert.equal(above.topicId, 't1');
  assert.equal(above.label, 'Mindrop');
});

test('decideForItem: الحدّ نفسه يُعد مطابقة (>= لا >)', () => {
  const topics = [{ id: 't1', label: 'Mindrop', embedding: BASE }];
  const v = vectorWithSimilarity(0.9);
  // نمرّر التشابه المحسوب فعليًا كعتبة بدل ما نعتمد على رجوع
  // cos(acos(x)) لنفس x بالضبط — دورة عائمة كهذي تطلع أحيانًا
  // 0.8999999999 فيصير الاختبار هشًّا بلا سبب حقيقي.
  const sim = cosineSimilarity(v, BASE);
  assert.equal(decideForItem(v, topics, sim).action, 'suggest');
});

test('decideForItem: **ما يربط تلقائيًا أبدًا** حتى عند تطابق تام', () => {
  const topics = [{ id: 't1', label: 'Mindrop', embedding: BASE }];
  const d = decideForItem([1, 0], topics);
  assert.equal(d.action, 'suggest', 'تطابق 1.0 يبقى اقتراحًا لا ربطًا');
  assert.equal(d.score, 1);
});

test('bestMatch: يختار الأعلى تشابهًا لا الأول', () => {
  const topics = [
    { id: 'far', label: 'far', embedding: vectorWithSimilarity(0.5) },
    { id: 'near', label: 'near', embedding: vectorWithSimilarity(0.95) },
    { id: 'mid', label: 'mid', embedding: vectorWithSimilarity(0.8) },
  ];
  assert.equal(bestMatch(BASE, topics).topic.id, 'near');
});

test('mergedEmbedding: متوسط مرجّح يزحف ولا يقفز', () => {
  // موضوع فيه 3 عناصر عند [1,0] يلتحق به عنصر عند [0,1].
  const merged = mergedEmbedding([1, 0], [0, 1], 3);
  assert.deepEqual(merged, [0.75, 0.25]);
  // أقرب للقديم منه للجديد — هذا المقصود.
  assert.ok(cosineSimilarity(merged, [1, 0]) > cosineSimilarity(merged, [0, 1]));
});

test('mergedEmbedding: طول غير متطابق يبقي القديم بدل ما يفسده', () => {
  assert.deepEqual(mergedEmbedding([1, 0], [1, 0, 0], 1), [1, 0]);
});

test('topicItemId: ثابت لنفس المدخل، ولا يتأثر بالترتيب', () => {
  const a = topicItemId('rec1', 'Mindrop');
  const b = topicItemId('rec1', '  mindrop  ');
  assert.equal(a, b, 'يتجاهل الفراغات وحالة الأحرف');
  assert.notEqual(a, topicItemId('rec2', 'Mindrop'), 'يختلف باختلاف التسجيل');
});

test('buildTopicItems: معرّفات فريدة حتى مع تكرار نفس النص', () => {
  const items = buildTopicItems('rec1', ['Mindrop', 'GitHub', 'Mindrop']);
  const ids = items.map((i) => i.itemId);
  assert.equal(new Set(ids).size, 3, 'التكرار ما يولّد معرّفًا مكرّرًا');
  assert.equal(items[0].text, 'Mindrop');
});

test('buildTopicItems: المعرّف يصمد لو انعكس ترتيب المصفوفة', () => {
  const forward = buildTopicItems('rec1', ['alpha', 'beta']);
  const reversed = buildTopicItems('rec1', ['beta', 'alpha']);
  const idOf = (list, text) => list.find((i) => i.text === text).itemId;
  assert.equal(idOf(forward, 'alpha'), idOf(reversed, 'alpha'));
  assert.equal(idOf(forward, 'beta'), idOf(reversed, 'beta'));
});

test('التسلسل الكامل: عنصران متشابهان بنفس التسجيل ما ينتجان موضوعين', () => {
  // نحاكي حلقة linkTopics: كل موضوع يُنشأ يدخل قائمة المرشّحين فورًا.
  const candidates = [];
  const vectors = [BASE, vectorWithSimilarity(0.99)];
  const actions = [];

  for (const v of vectors) {
    const d = decideForItem(v, candidates);
    actions.push(d.action);
    if (d.action === 'create') {
      candidates.push({ id: `t${candidates.length}`, label: 'x', embedding: v });
    }
  }

  assert.deepEqual(actions, ['create', 'suggest']);
  assert.equal(candidates.length, 1, 'موضوع واحد فقط أُنشئ');
});
