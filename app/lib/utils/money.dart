/// Currency display is `NGN 1,240,000` — no naira glyph (docs/00-START-HERE.md).
String ngn(num amount) => 'NGN ${groupThousands(amount.round())}';

String groupThousands(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// Short form for dense tables, e.g. `NGN 1.24m`.
String ngnShort(num amount) {
  if (amount >= 1000000) {
    final m = amount / 1000000;
    return 'NGN ${m.toStringAsFixed(m >= 10 ? 1 : 2).replaceFirst(RegExp(r'\.?0+$'), '')}m';
  }
  if (amount >= 1000) return 'NGN ${(amount / 1000).round()}k';
  return ngn(amount);
}

/// `*******1234` — only the last four digits ever leave the KYC step.
String maskId(String digits) {
  if (digits.length <= 4) return digits;
  return '${'*' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
}

/// Reference = `FT-` + first 8 of the application uuid.
String reference(String applicationId) =>
    'FT-${applicationId.replaceAll('-', '').substring(0, 8).toUpperCase()}';
