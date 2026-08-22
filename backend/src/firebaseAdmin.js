import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import fs from 'node:fs';

// ---------------------------------------------------------------------------
// تهيئة Firebase Admin SDK — يُستخدم للتحقق الحقيقي من هوية المستخدم
// (verifyIdToken) بدل الثقة بأي uid يرسله التطبيق كنص عادي بدون إثبات.
//
// نستخدم الاستيراد المقسّم (firebase-admin/app، firebase-admin/auth) بدل
// `import admin from 'firebase-admin'` القديم. النمط القديم فيه مشكلة
// معروفة مع ESM ("type": "module"): admin.credential يطلع undefined لأن
// التوافق بين CommonJS وESM ما يجمّع الـ namespace القديم صح. النمط
// المقسّم مبني خصيصًا ليشتغل صح مع ESM.
//
// ---------------------------------------------------------------------------
// مصدر المفتاح: متغيّر بيئة أولًا، ثم ملف محلي كاحتياط.
//
// **ليش base64 مو JSON خام:** مفتاح حساب الخدمة يحتوي private key بصيغة
// PEM فيها أسطر جديدة حقيقية (\n). لصق JSON خام بحقل متغيّرات البيئة عند
// أي مستضيف يفسد هذي الأسطر غالبًا (تتحوّل لـ \\n أو تُحذف)، والنتيجة خطأ
// غامض وقت التشغيل:
//   error:0909006C:PEM routines:get_name:no start line
// أما base64 فسطر واحد بلا مسافات ولا أسطر — يمر سليمًا عبر أي واجهة.
//
// الترتيب مقصود: الإنتاج ما عنده قرص ثابت أصلًا، والتطوير المحلي يبقى
// شغّالًا بالملف نفسه بدون أي تغيير.
// ---------------------------------------------------------------------------

function loadServiceAccount() {
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  if (b64 && b64.trim().length > 0) {
    let decoded;
    try {
      decoded = Buffer.from(b64.trim(), 'base64').toString('utf8');
    } catch (err) {
      throw new Error(
        `FIREBASE_SERVICE_ACCOUNT_B64 مو base64 صالح: ${err.message}`,
      );
    }
    try {
      return JSON.parse(decoded);
    } catch (err) {
      throw new Error(
        'FIREBASE_SERVICE_ACCOUNT_B64 فُكّ ترميزه لكنه مو JSON صالح — ' +
          `تأكد إنك رمّزت الملف كامل: ${err.message}`,
      );
    }
  }

  // احتياط التطوير المحلي: نفس المسار القديم بالضبط.
  const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (keyPath && fs.existsSync(keyPath)) {
    return JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  }

  throw new Error(
    'ما فيه مفتاح Firebase. للإنتاج: حط FIREBASE_SERVICE_ACCOUNT_B64 ' +
      '(ناتج `base64 -i service-account.json`) بمتغيّرات البيئة عند المستضيف. ' +
      'للتطوير المحلي: خلّ FIREBASE_SERVICE_ACCOUNT_PATH يشير لملف موجود ' +
      '(راجع .env.example). السيرفر ما يقدر يتحقق من هوية أي مستخدم بدونه.',
  );
}

initializeApp({
  credential: cert(loadServiceAccount()),
});

export const auth = getAuth();
