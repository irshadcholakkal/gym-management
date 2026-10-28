class MembershipQuote {
  const MembershipQuote({
    required this.priceMinor,
    this.enrollmentFeeMinor = 0,
    this.discountMinor = 0,
    this.taxBasisPoints = 0,
  });
  final int priceMinor, enrollmentFeeMinor, discountMinor, taxBasisPoints;
  int get subtotalMinor => priceMinor + enrollmentFeeMinor;
  int get taxableMinor => subtotalMinor - discountMinor;
  int get taxMinor =>
      ((BigInt.from(taxableMinor) * BigInt.from(taxBasisPoints) +
                  BigInt.from(5000)) ~/
              BigInt.from(10000))
          .toInt();
  int get totalMinor => taxableMinor + taxMinor;
}
