const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

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
// Runs server-side categorization as a backup if category is 'Other'
// ──────────────────────────────────────────────────────────────────────────────
exports.onTransactionCreated = functions.firestore.onDocumentCreated(
  'users/{userId}/transactions/{txId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (data.category !== 'Other') return; // Already categorized

    const merchant = data.merchant || '';
    const category = categorize(merchant);

    if (category !== 'Other') {
      await snap.ref.update({ category });
    }
  }
);

// ──────────────────────────────────────────────────────────────────────────────
// Cloud Function: computeMonthlySummary
// Called on-demand or by a scheduler to pre-compute monthly summaries
// for faster dashboard loads at scale.
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
      userId,
      year,
      month,
      totalIncome,
      totalExpense,
      netSavings: totalIncome - totalExpense,
      savingsRate: totalIncome > 0 ? (totalIncome - totalExpense) / totalIncome : 0,
      categoryBreakdown,
      transactionCount: snap.size,
      computedAt: new Date().toISOString(),
    };

    // Cache in Firestore
    await db
      .collection('users')
      .doc(userId)
      .collection('monthlySummaries')
      .doc(`${year}-${String(month).padStart(2, '0')}`)
      .set(summary);

    return summary;
  }
);
