import '../theme/app_colors.dart';

/// Maps category names to their emoji and color
class AppCategories {
  static const List<CategoryInfo> all = [
    CategoryInfo(
      name: 'Food & Dining',
      emoji: '🍔',
      color: AppColors.catFood,
      keywords: [
        'swiggy', 'zomato', 'dominos', 'pizza', 'mcdonalds', 'kfc',
        'starbucks', 'restaurant', 'hotel', 'cafe', 'food', 'eat',
        'biryani', 'burger', 'subway', 'burger king', 'dunkin',
        'barbeque', 'bbq', 'fassos', 'box8', 'freshmenu', 'uber eats',
        'dunzo food', 'bakery', 'tea', 'coffee', 'juice',
      ],
    ),
    CategoryInfo(
      name: 'Transport',
      emoji: '🚗',
      color: AppColors.catTransport,
      keywords: [
        'uber', 'ola', 'rapido', 'redbus', 'irctc', 'petrol', 'fuel',
        'diesel', 'metro', 'bmtc', 'dtc', 'auto', 'taxi', 'cab',
        'parking', 'toll', 'fastag', 'train', 'bus', 'flight', 'rapido',
        'blinkit delivery', 'porter', 'namma yatri', 'yulu', 'bounce',
      ],
    ),
    CategoryInfo(
      name: 'Shopping',
      emoji: '🛍️',
      color: AppColors.catShopping,
      keywords: [
        'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa',
        'bigbasket', 'grofers', 'blinkit', 'instamart', 'zepto',
        'snapdeal', 'tata cliq', 'reliance', 'dmarts', 'dmart',
        'shopping', 'mall', 'store', 'market', 'purchase', 'buy',
      ],
    ),
    CategoryInfo(
      name: 'Utilities',
      emoji: '💡',
      color: AppColors.catUtilities,
      keywords: [
        'jio', 'airtel', 'bsnl', 'vodafone', 'vi', 'tata sky', 'dish tv',
        'electricity', 'bescom', 'tata power', 'adani electricity',
        'water', 'gas', 'lpg', 'cylinder', 'broadband', 'wifi',
        'internet', 'recharge', 'mobile bill', 'postpaid', 'prepaid',
      ],
    ),
    CategoryInfo(
      name: 'Housing',
      emoji: '🏠',
      color: AppColors.catHousing,
      keywords: [
        'rent', 'maintenance', 'society', 'housing', 'apartment',
        'flat', 'pg', 'hostel', 'landlord', 'lease', 'deposit',
        'property tax', 'home loan', 'emi', 'mortgage',
      ],
    ),
    CategoryInfo(
      name: 'Health',
      emoji: '🏥',
      color: AppColors.catHealth,
      keywords: [
        'pharmacy', 'apollo', 'medplus', 'hospital', 'clinic',
        'doctor', 'medical', 'medicine', 'health', 'lab', 'test',
        'diagnostic', 'pharmeasy', 'netmeds', 'tata 1mg',
        '1mg', 'practo', 'insurance', 'health insurance',
      ],
    ),
    CategoryInfo(
      name: 'Entertainment',
      emoji: '🎬',
      color: AppColors.catEntertainment,
      keywords: [
        'netflix', 'hotstar', 'disney', 'amazon prime', 'youtube',
        'spotify', 'apple music', 'gaana', 'wynk', 'bookmyshow',
        'pvr', 'inox', 'movie', 'cinema', 'concert', 'event',
        'gaming', 'steam', 'playstation', 'xbox', 'zee5',
        'sonyliv', 'voot', 'jiocinema', 'mxplayer',
      ],
    ),
    CategoryInfo(
      name: 'Education',
      emoji: '📚',
      color: AppColors.catEducation,
      keywords: [
        'udemy', 'coursera', 'unacademy', 'byju', 'vedantu', 'toppr',
        'school', 'college', 'university', 'fees', 'tuition', 'course',
        'book', 'study', 'exam', 'coaching', 'khan academy',
        'linkedin learning', 'skillshare', 'simplilearn',
      ],
    ),
    CategoryInfo(
      name: 'Travel',
      emoji: '✈️',
      color: AppColors.catTravel,
      keywords: [
        'makemytrip', 'goibibo', 'oyo', 'cleartrip', 'booking.com',
        'airbnb', 'flight', 'hotel', 'resort', 'travel', 'vacation',
        'holiday', 'indigo', 'air india', 'spicejet', 'vistara',
        'akasa', 'trip', 'tour', 'passport', 'visa',
      ],
    ),
    CategoryInfo(
      name: 'Income',
      emoji: '💰',
      color: AppColors.catIncome,
      keywords: [
        'salary', 'credit', 'income', 'deposit', 'received',
        'refund', 'cashback', 'reward', 'dividend', 'interest',
        'bonus', 'payroll', 'neft received', 'imps received',
        'upi received', 'transfer received',
      ],
    ),
    CategoryInfo(
      name: 'Other',
      emoji: '📦',
      color: AppColors.catOther,
      keywords: [],
    ),
  ];

  static CategoryInfo getCategory(String name) {
    return all.firstWhere(
      (c) => c.name == name,
      orElse: () => all.last,
    );
  }

  static List<String> get names => all.map((c) => c.name).toList();
}

class CategoryInfo {
  final String name;
  final String emoji;
  final dynamic color; // Color
  final List<String> keywords;

  const CategoryInfo({
    required this.name,
    required this.emoji,
    required this.color,
    required this.keywords,
  });
}
