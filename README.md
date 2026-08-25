# AniManga — Supabase Final

نسخة جاهزة للربط الحقيقي مع Supabase وVercel، بدون أعمال وهمية.

## المزايا
- Supabase Auth لتسجيل/دخول الحسابات.
- أول حساب ينفذ bootstrap يصبح Owner تلقائيًا.
- رتب وصلاحيات قابلة للتخصيص: Owner / Admin / Editor / Uploader / Member.
- إنشاء رتب جديدة وتحديد الصلاحيات من لوحة الإدارة.
- تعيين رتبة للمستخدمين.
- قاعدة بيانات للأعمال والفصول والصفحات والنقاط وفتح الفصول.
- Supabase Storage خاص لصفحات الفصول.
- رفع عدة صور من الهاتف وترتيبها رقميًا.
- روابط صور موقعة مؤقتة للصفحات لحماية المحتوى الخاص.
- فصول مجانية أو مدفوعة بالنقاط.
- فتح الفصل عبر RPC آمن يخصم النقاط من قاعدة البيانات.
- واجهة عربية متجاوبة.

## تشغيل محلي
1. انسخ `.env.example` إلى `.env.local`.
2. ضع VITE_SUPABASE_URL و VITE_SUPABASE_PUBLISHABLE_KEY.
3. في Supabase SQL Editor شغّل `supabase/schema.sql` كاملًا.
4. `npm install`
5. `npm run dev`

## Vercel
Build command: `npm run build`
Output directory: `dist`
Environment Variables: نفس متغيري Supabase الموجودين في `.env.local`.

## مهم
- لا تضع service_role key في الواجهة.
- التخزين خاص (private). الصفحات تُعرض بروابط signed مؤقتة.
- نظام شراء النقاط الحقيقي يحتاج Edge Function/Webhook لمزود الدفع (Binance Pay أو مزود محافظ آخر). لا تعتمد على زر في الواجهة لمنح نقاط حقيقية.
- سياسات RLS موجودة في schema.sql.
