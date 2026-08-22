import express from 'express';
import healthRouter from './routes/health.js';
import recordingsRouter from './routes/recordings.js';

// ---------------------------------------------------------------------------
// mindrop-backend
//
// الحالة الحين: فحص صحة + استقبال رفع الصوت وتخزينه على قرص السيرفر.
// لسا ما فيه: تحقق هوية حقيقي (Firebase ID token)، ولا تفريغ (Qwen)، ولا
// اتصال بـ Firestore. كل وحدة فيهم خطوة جاية منفصلة، خطوة خطوة.
// ---------------------------------------------------------------------------

const app = express();
const PORT = process.env.PORT || 8787;

app.use(healthRouter);
app.use(recordingsRouter);

// معالج أخطاء عام: يحوّل أي خطأ (مثل تجاوز حجم الملف من multer) لرد JSON
// بدل صفحة HTML افتراضية من Express. لازم يكون آخر شي ومعه 4 معاملات
// عشان Express يتعرف عليه كـ error handler.
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'خطأ غير متوقع' });
});

app.listen(PORT, () => {
  console.log(`mindrop-backend listening on http://localhost:${PORT}`);
});
