enum IpoCategory { mainline, sme }

enum IpoStatus { ongoing, upcoming, closed, listed }

enum GmpTrend { up, down, flat }

class IpoSubscription {
  final double qib;
  final double nii;
  final double retail;
  final double? employee;
  final double total;
  final String updatedAt;

  const IpoSubscription({
    required this.qib,
    required this.nii,
    required this.retail,
    this.employee,
    required this.total,
    required this.updatedAt,
  });
}

class IpoFinancialYear {
  final String year;
  final double revenueCr;
  final double patCr;
  final double netWorthCr;
  final double assetsCr;

  const IpoFinancialYear({
    required this.year,
    required this.revenueCr,
    required this.patCr,
    required this.netWorthCr,
    required this.assetsCr,
  });
}

class IpoItem {
  final String id;
  final String name;
  final String symbol;
  final String logoEmoji;
  final String sector;
  final IpoCategory category;
  final IpoStatus status;
  final double priceBandMin;
  final double priceBandMax;
  final int lotSize;
  final double issueSizeCr;
  final double faceValue;
  final double gmpAmount;
  final double gmpPercent;
  final GmpTrend gmpTrend;
  final DateTime openDate;
  final DateTime closeDate;
  final DateTime allotmentDate;
  final DateTime refundDate;
  final DateTime listingDate;
  final IpoSubscription subscription;
  final List<IpoFinancialYear> financials;
  final double peRatio;
  final double eps;
  final double ronw;
  final double? marketCapCr;
  final String registrarName;
  final String registrarUrl;
  final String about;
  final List<String> objectsOfIssue;
  final double? listedPrice;
  final double? listingGainPercent;
  final bool isBookmarked;

  const IpoItem({
    required this.id,
    required this.name,
    required this.symbol,
    required this.logoEmoji,
    required this.sector,
    required this.category,
    required this.status,
    required this.priceBandMin,
    required this.priceBandMax,
    required this.lotSize,
    required this.issueSizeCr,
    required this.faceValue,
    required this.gmpAmount,
    required this.gmpPercent,
    required this.gmpTrend,
    required this.openDate,
    required this.closeDate,
    required this.allotmentDate,
    required this.refundDate,
    required this.listingDate,
    required this.subscription,
    required this.financials,
    required this.peRatio,
    required this.eps,
    required this.ronw,
    this.marketCapCr,
    required this.registrarName,
    required this.registrarUrl,
    required this.about,
    required this.objectsOfIssue,
    this.listedPrice,
    this.listingGainPercent,
    this.isBookmarked = false,
  });

  double get minInvestment => priceBandMax * lotSize;
  double get estimatedListingPrice => priceBandMax + gmpAmount;

  IpoItem copyWith({
    bool? isBookmarked,
  }) {
    return IpoItem(
      id: id,
      name: name,
      symbol: symbol,
      logoEmoji: logoEmoji,
      sector: sector,
      category: category,
      status: status,
      priceBandMin: priceBandMin,
      priceBandMax: priceBandMax,
      lotSize: lotSize,
      issueSizeCr: issueSizeCr,
      faceValue: faceValue,
      gmpAmount: gmpAmount,
      gmpPercent: gmpPercent,
      gmpTrend: gmpTrend,
      openDate: openDate,
      closeDate: closeDate,
      allotmentDate: allotmentDate,
      refundDate: refundDate,
      listingDate: listingDate,
      subscription: subscription,
      financials: financials,
      peRatio: peRatio,
      eps: eps,
      ronw: ronw,
      marketCapCr: marketCapCr,
      registrarName: registrarName,
      registrarUrl: registrarUrl,
      about: about,
      objectsOfIssue: objectsOfIssue,
      listedPrice: listedPrice,
      listingGainPercent: listingGainPercent,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}
