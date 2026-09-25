// Seed fixtures — dummy data only. Mirrors fixtures/ and supabase/seed.sql.
// No real customer PII belongs in this repo.

import '../models/enums.dart';

class SandboxIdentity {
  const SandboxIdentity(this.bvn, this.nin, this.matchedName, this.result);
  final String bvn;
  final String nin;
  final String matchedName;
  final KycResult result;
}

const kycSandbox = <SandboxIdentity>[
  SandboxIdentity('22222222222', '11111111111', 'ADA EZE OKAFOR', KycResult.sandboxPass),
  SandboxIdentity('33333333333', '11111111112', 'IBRAHIM MUSA', KycResult.sandboxPass),
  SandboxIdentity('44444444444', '11111111113', 'CHIOMA KALU', KycResult.sandboxPass),
  SandboxIdentity('55555555555', '11111111114', 'NORTHSHORE SIGNATORY', KycResult.sandboxPass),
  SandboxIdentity('00000000000', '00000000000', 'FAIL CASE', KycResult.sandboxFail),
];

const smsAdaeze = '''GTBank Credit Alert: NGN 420000.00 from ACME NIGERIA LTD SALARY on 25-JUN. Bal: 512400.00
GTBank Debit Alert: NGN 15000.00 to CARBON LOAN REPAY on 28-JUN. Bal: 497400.00
GTBank Debit Alert: NGN 8500.00 POS JUMIA on 02-JUL. Bal: 488900.00
GTBank Debit Alert: NGN 3200.00 AIRTIME MTN on 03-JUL. Bal: 485700.00
GTBank Credit Alert: NGN 420000.00 from ACME NIGERIA LTD SALARY on 25-JUL. Bal: 610200.00
GTBank Debit Alert: NGN 15000.00 to CARBON LOAN REPAY on 28-JUL. Bal: 595200.00
GTBank Debit Alert: NGN 12000.00 POS SHOPRITE on 05-AUG. Bal: 583200.00
GTBank Credit Alert: NGN 420000.00 from ACME NIGERIA LTD SALARY on 25-AUG. Bal: 640000.00
GTBank Debit Alert: NGN 15000.00 to CARBON LOAN REPAY on 28-AUG. Bal: 625000.00
GTBank Debit Alert: NGN 4500.00 AIRTIME GLO on 01-SEP. Bal: 620500.00''';

const smsIbrahim = '''Access Bank Credit: NGN 90000 TRANSFER FROM K. BELLO 03-JUN Bal 91000
Access Bank Debit: NGN 40000 PALMPAY on 04-JUN Bal 51000
Access Bank Debit: NGN 25000 LOAN REPAY UNKNOWN on 05-JUN Bal 26000
Access Bank Debit: NGN 8000 POS 06-JUN REVERSAL NGN 8000 07-JUN
Access Bank Credit: NGN 310000 POS SALES 18-JUN Bal 328000
Access Bank Debit: NGN 40000 PALMPAY 04-JUL Bal 120000
Access Bank Credit: NGN 150000 TRANSFER 12-JUL Bal 270000
Access Bank Debit: NGN 25000 LOAN REPAY UNKNOWN 05-JUL Bal 245000
Access Bank Credit: NGN 280000 MIXED INFLOWS 20-AUG Bal 190000
Access Bank Debit: NGN 40000 PALMPAY 04-AUG Bal 150000''';

const smsNorthshore = '''Zenith Credit: NGN 2100000 NORTHSHORE TRADING LTD SALES 04-JUN Bal 2380000
Zenith Debit: NGN 640000 TRF TO SUPPLIER ADEX FOODS 09-JUN Bal 1740000
Zenith Credit: NGN 950000 POS SETTLEMENT 21-JUN Bal 2690000
Zenith Debit: NGN 610000 TRF TO SUPPLIER ADEX FOODS 08-JUL Bal 2080000
Zenith Credit: NGN 1300000 NORTHSHORE TRADING LTD SALES 15-JUL Bal 3380000
Zenith Debit: NGN 420000 PAYROLL JUL 28-JUL Bal 2960000
Zenith Credit: NGN 2050000 NORTHSHORE TRADING LTD SALES 11-AUG Bal 5010000
Zenith Debit: NGN 600000 TRF TO SUPPLIER ADEX FOODS 13-AUG Bal 4410000
Zenith Debit: NGN 420000 PAYROLL AUG 28-AUG Bal 3990000
Zenith Credit: NGN 1000000 POS SETTLEMENT 30-AUG Bal 4990000''';

/// extract_cache rows keyed by `fixture:*` (same payloads as seed.sql).
const extractFixtures = <String, Map<String, dynamic>>{
  'fixture:adaeze-sms': {
    'monthly_income_est': 420000,
    'income_regularity': 'stable',
    'inflow_months_observed': 3,
    'top_spend_categories': [
      {'category': 'pos_retail', 'monthly_avg': 85000, 'share_of_outflow': 0.31},
      {'category': 'airtime_data', 'monthly_avg': 18000, 'share_of_outflow': 0.07},
    ],
    'existing_loan_debits': [
      {'label': 'Carbon', 'monthly_avg': 15000},
    ],
    'overdraft_or_reversals': false,
    'average_balance_proxy': 190000,
    'confidence': 0.82,
    'warnings': ['external_lender_detected'],
  },
  'fixture:ibrahim-sms': {
    'monthly_income_est': 280000,
    'income_regularity': 'lumpy',
    'inflow_months_observed': 3,
    'top_spend_categories': [
      {'category': 'transfers_out', 'monthly_avg': 90000, 'share_of_outflow': 0.4},
    ],
    'existing_loan_debits': [
      {'label': 'Palmpay', 'monthly_avg': 40000},
      {'label': 'unknown lender', 'monthly_avg': 25000},
    ],
    'overdraft_or_reversals': true,
    'average_balance_proxy': 22000,
    'confidence': 0.6,
    'warnings': ['external_lender_detected', 'irregular_income', 'reversals_present'],
  },
  'fixture:northshore-sms': {
    'monthly_income_est': 1800000,
    'income_regularity': 'lumpy',
    'inflow_months_observed': 3,
    'top_spend_categories': [
      {'category': 'suppliers', 'monthly_avg': 620000, 'share_of_outflow': 0.45},
    ],
    'existing_loan_debits': [],
    'overdraft_or_reversals': false,
    'average_balance_proxy': 740000,
    'confidence': 0.7,
    'warnings': ['irregular_income'],
  },
};

/// Pick the fixture for a pasted SMS blob, if it is one of the seed files.
String? fixtureKeyFor(String sms) {
  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
  final n = norm(sms);
  if (n == norm(smsAdaeze)) return 'fixture:adaeze-sms';
  if (n == norm(smsIbrahim)) return 'fixture:ibrahim-sms';
  if (n == norm(smsNorthshore)) return 'fixture:northshore-sms';
  return null;
}

class Persona {
  const Persona(this.key, this.label, this.bvn, this.nin, this.sms);
  final String key;
  final String label;
  final String bvn;
  final String nin;
  final String sms;
}

const personas = <Persona>[
  Persona('adaeze', 'Adaeze O.', '22222222222', '11111111111', smsAdaeze),
  Persona('ibrahim', 'Ibrahim M.', '33333333333', '11111111112', smsIbrahim),
  Persona('northshore', 'Northshore Trading', '55555555555', '11111111114', smsNorthshore),
];
