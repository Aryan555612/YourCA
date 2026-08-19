const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');
const https = require('https');

admin.initializeApp();
const db = admin.firestore();

// ──────────────────────────────────────────────────────────────────────────────
// Brevo REST API Configuration
// ──────────────────────────────────────────────────────────────────────────────
const BREVO_API_KEY = process.env.BREVO_API_KEY || 'YOUR_BREVO_API_KEY_HERE';

const SENDER_EMAIL = 'aryanpatel9051@gmail.com';
const SENDER_NAME = 'YourCA Finance';

function sendBrevoEmail(toEmail, code) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      sender: { name: SENDER_NAME, email: SENDER_EMAIL },
      to: [{ email: toEmail }],
      subject: `${code} - Your YourCA verification code`,
      htmlContent: `
        <div style="font-family: Arial, sans-serif; background: #0d0e15; padding: 40px 20px;">
          <div style="max-width: 480px; margin: auto; background: #161824; border-radius: 20px; padding: 40px; border: 1px solid #2d2f45;">
            <h1 style="color: #6C5CE7; text-align: center; margin: 0 0 8px 0; font-size: 28px;">YourCA Finance</h1>
            <p style="color: #a0a0b0; text-align: center; margin: 0 0 32px 0; font-size: 14px;">Personal Finance Planner</p>
            <p style="color: #e0e0e0; font-size: 16px; text-align: center; margin-bottom: 24px;">
              Your 6-digit login verification code:
            </p>
            <div style="background: #0d0e15; border-radius: 16px; padding: 28px; text-align: center; border: 2px solid #6C5CE7; margin-bottom: 24px;">
              <span style="font-size: 48px; font-weight: 900; letter-spacing: 14px; color: #6C5CE7; font-family: monospace;">${code}</span>
            </div>
            <p style="color: #707080; font-size: 13px; text-align: center; margin: 0;">
              This code expires in <strong style="color: #a0a0b0;">10 minutes</strong>.<br/>
              If you did not request this, ignore this email.
            </p>
          </div>
        </div>
      `
    });

    const req = https.request({
      hostname: 'api.brevo.com',
      port: 443,
      path: '/v3/smtp/email',
      method: 'POST',
      headers: {
        'api-key': BREVO_API_KEY,
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
      }
    }, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => responseBody += chunk);
      res.on('end', () => {
        console.log(`Brevo API response: ${res.statusCode} - ${responseBody}`);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(responseBody));
        } else {
          reject(new Error(`Brevo API error ${res.statusCode}: ${responseBody}`));
        }
      });
    });

    req.on('error', (e) => reject(e));
    req.write(body);
    req.end();
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// Cloud Function: sendOtpEmail
// Called from the Flutter app to send a real 6-digit OTP to the user's Gmail
// ──────────────────────────────────────────────────────────────────────────────
exports.sendOtpEmail = functions.https.onCall(
  { maxInstances: 10 },
  async (request) => {
    const { email, code } = request.data;

    if (!email || !code) {
      throw new functions.https.HttpsError('invalid-argument', 'Email and code are required.');
    }

    const cleanEmail = email.toLowerCase().trim();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    // Save OTP to Firestore as cloud backup for verification
    try {
      const docId = `${cleanEmail}_${code}`;
      await db.collection('otps').doc(docId).set({
        email: cleanEmail,
        code: code,
        expires_at: expiresAt,
        created_at: new Date().toISOString(),
      });
    } catch (err) {
      console.warn('Could not save OTP to Firestore:', err.message);
    }

    // Send the real OTP email via Brevo REST API
    try {
      const result = await sendBrevoEmail(cleanEmail, code);
      console.log(`OTP email sent to ${cleanEmail}:`, result);
      return { success: true };
    } catch (err) {
      console.error('Failed to send OTP email:', err);
      throw new functions.https.HttpsError('internal', `Email delivery failed: ${err.message}`);

    }
  }
);

// ──────────────────────────────────────────────────────────────────────────────
// Category keyword map (mirrors the Flutter app's categorization_service.dart)
// ──────────────────────────────────────────────────────────────────────────────
const CATEGORY_KEYWORDS = {
  'Food & Dining': ['swiggy','zomato','dominos','pizza','mcdonalds','kfc','starbucks','restaurant','hotel','cafe','food','eat','biryani','burger','subway','bakery','coffee','juice'],
  'Transport': ['uber','ola','rapido','redbus','irctc','petrol','fuel','diesel','metro','auto','taxi','cab','parking','toll','fastag','train','bus','flight'],
  'Shopping': ['amazon','flipkart','myntra','ajio','meesho','nykaa','bigbasket','blinkit','zepto','dmart','shopping','mall','store','market'],
  'Utilities': ['jio','airtel','bsnl','vodafone','vi','electricity','bescom','water','gas','lpg','broadband','wifi','internet','recharge','postpaid','prepaid'],
  'Housing': ['rent','maintenance','society','housing','apartment','flat','pg','hostel','property tax','home loan','emi','mortgage'],
  'Health': ['pharmacy','apollo','medplus','hospital','clinic','doctor','medical','medicine','lab','diagnostic','pharmeasy','1mg'],
  'Entertainment': ['netflix','hotstar','disney','amazon prime','spotify','apple music','bookmyshow','pvr','inox','movie','cinema','gaming'],
  'Education': ['udemy','coursera','unacademy','byju','vedantu','school','college','fees','tuition','course','coaching'],
  'Travel': ['makemytrip','goibibo','oyo','cleartrip','booking','airbnb','flight','hotel','resort','travel','indigo','air india','spicejet'],
  'Income': ['salary','credit','income','deposit','received','refund','cashback','reward','dividend','interest','bonus'],
};

function categorize(text) {
  const lower = text.toLowerCase().trim();
  for (const [cat, keywords] of Object.entries(CATEGORY_KEYWORDS)) {
    if (cat === 'Income') continue;
    for (const kw of keywords) {
      if (lower.includes(kw)) return cat;
    }
  }
  return 'Other';
}

// ──────────────────────────────────────────────────────────────────────────────
// Cloud Function: onTransactionCreated
// ──────────────────────────────────────────────────────────────────────────────
exports.onTransactionCreated = functions.firestore.onDocumentCreated(
  'users/{userId}/transactions/{txId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.category !== 'Other') return;
    const merchant = data.merchant || '';
    const category = categorize(merchant);
    if (category !== 'Other') {
      await snap.ref.update({ category });
    }
  }
);

// ──────────────────────────────────────────────────────────────────────────────
// Cloud Function: computeMonthlySummary
// ──────────────────────────────────────────────────────────────────────────────
exports.computeMonthlySummary = functions.https.onCall(
  { maxInstances: 10 },
  async (request) => {
    const { userId, year, month } = request.data;
    if (!userId || !year || !month) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing userId, year, or month');
    }

    const start = new Date(year, month - 1, 1).toISOString();
    const end = new Date(year, month, 0, 23, 59, 59).toISOString();

    const snap = await db
      .collection('users')
      .doc(userId)
      .collection('transactions')
      .where('date', '>=', start)
      .where('date', '<=', end)
      .get();

    let totalIncome = 0;
    let totalExpense = 0;
    const categoryBreakdown = {};

    snap.forEach((doc) => {
      const tx = doc.data();
      if (tx.type === 'credit') {
        totalIncome += tx.amount;
      } else {
        totalExpense += tx.amount;
        categoryBreakdown[tx.category] = (categoryBreakdown[tx.category] || 0) + tx.amount;
      }
    });

    const summary = {
      userId, year, month, totalIncome, totalExpense,
      netSavings: totalIncome - totalExpense,
      savingsRate: totalIncome > 0 ? (totalIncome - totalExpense) / totalIncome : 0,
      categoryBreakdown,
      transactionCount: snap.size,
      computedAt: new Date().toISOString(),
    };

    await db
      .collection('users')
      .doc(userId)
      .collection('monthlySummaries')
      .doc(`${year}-${String(month).padStart(2, '0')}`)
      .set(summary);

    return summary;
  }
);
