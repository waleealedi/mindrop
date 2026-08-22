import { auth } from '../firebaseAdmin.js';

// ---------------------------------------------------------------------------
// أي نقطة تحتاج تعرف هوية المستخدم الحقيقية (زي رفع تسجيل) تمر من هذا
// الميدلوير أول شي. يقرأ Authorization: Bearer <idToken>، يتحقق منه فعليًا
// عند Firebase (مو مجرد فك تشفير محلي ساذج)، ويحط uid الحقيقي بـ req.uid.
//
// من هذي النقطة، الـ uid ما يوصلنا من التطبيق كنص عادي نصدقه على كلامه —
// يوصلنا من توكن موقّع رقميًا من Firebase نفسه، ما يقدر أحد يزوّره.
// ---------------------------------------------------------------------------
export async function verifyToken(req, res, next) {
  const header = req.headers.authorization || '';
  const idToken = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!idToken) {
    return res.status(401).json({ error: 'ناقص Authorization: Bearer <token>' });
  }

  try {
    const decoded = await auth.verifyIdToken(idToken);
    req.uid = decoded.uid;
    next();
  } catch (err) {
    res.status(401).json({ error: 'توكن غير صالح أو منتهي' });
  }
}
