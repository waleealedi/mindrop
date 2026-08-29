import assert from 'node:assert/strict';
import test from 'node:test';

import { validateExtraction } from '../src/services/analysis.js';

// ---------------------------------------------------------------------------
// التحقّق الدفاعي بعد Groq — بلا شبكة وبلا مفتاح.
//
// الوحدة تحت الاختبار هي **عقد الشكل**، لا جودة العنوان: هل يُرفض ناتج
// ناقص العنوان، وهل تُنظَّف القيمة قبل ما تتخزّن. جودة الصياغة قرار موديل
// ما ينفع نثبّته باختبار.
// ---------------------------------------------------------------------------

/// ناتج صحيح كامل — نبني منه الحالات الناقصة بدل تكراره كل مرة.
function valid(overrides = {}) {
  return {
    title: 'Weekly planning notes',
    tasks: ['call the bank'],
    goals: [],
    ideas: [],
    topics: ['planning'],
    ...overrides,
  };
}

test('العنوان الصالح يمر كما هو', () => {
  const out = validateExtraction(valid());
  assert.equal(out.title, 'Weekly planning notes');
});

test('العنوان الناقص يرمي — مطلوب لا اختياري', () => {
  const { title, ...withoutTitle } = valid();
  assert.throws(() => validateExtraction(withoutTitle), /title/);
});

test('العنوان بنوع غلط يرمي', () => {
  for (const bad of [null, 42, ['a'], { a: 1 }]) {
    assert.throws(() => validateExtraction(valid({ title: bad })), /title/);
  }
});

test('المسافات الزائدة والأسطر تُطبَّع لمسافة واحدة', () => {
  const out = validateExtraction(valid({ title: '  weekly   planning\n notes  ' }));
  assert.equal(out.title, 'weekly planning notes');
});

test('العنوان الطويل يُقصّ على 120 محرفًا', () => {
  const out = validateExtraction(valid({ title: 'x'.repeat(400) }));
  assert.equal(out.title.length, 120);
});

test('العنوان العربي يمر بلا تشويه', () => {
  const out = validateExtraction(valid({ title: 'خطة الأسبوع' }));
  assert.equal(out.title, 'خطة الأسبوع');
});

test('العنوان ما يكسر بقية الحقول', () => {
  const out = validateExtraction(valid({ tasks: ['  a  ', '', 'b'] }));
  assert.deepEqual(out.tasks, ['a', 'b']);
  assert.deepEqual(out.goals, []);
});

test('عنوان فاضي يمر كنص فاضي — الواجهة تتعامل معه كغياب عنوان', () => {
  // ما نرمي هنا عمدًا: الرمي يعني فقدان التحليل كله بسبب عنوان، والواجهة
  // عندها أصلًا سلسلة بدائل (نص مفرَّغ ← حالة) تغطي هذي الحالة.
  const out = validateExtraction(valid({ title: '   ' }));
  assert.equal(out.title, '');
});
