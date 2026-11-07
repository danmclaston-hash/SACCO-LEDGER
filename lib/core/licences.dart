/// Same content as docs/LICENCES.md, shown inside the app. Reviewed against public sources in Nov 2026.
class LicenceItem {
  final String name;
  final String regulator;
  final String law;
  final String why;
  const LicenceItem(this.name, this.regulator, this.law, this.why);
}

const licenceDisclaimer =
    'This is a guide, not legal advice. SACCO Ledger does not hold any licence on your behalf, and using this app is not a licence. '
    'Ask a Ugandan lawyer to confirm what applies before going live. Fees and rules change: check with each regulator.';

const groupLicences = [
  LicenceItem(
    'Register as a cooperative society',
    'Registrar of Cooperatives, Ministry of Trade',
    'Cooperative Societies Act',
    'A SACCO registers here first. UMRA asks for this certificate.',
  ),
  LicenceItem(
    'UMRA SACCO licence',
    'Uganda Microfinance Regulatory Authority',
    'Tier 4 Microfinance Institutions and Money Lenders Act, 2016',
    'A SACCO must hold a valid licence. It lasts one calendar year, to 31 December. Apply to renew at least 90 days before expiry. Record it above so the app warns you.',
  ),
  LicenceItem(
    'Large SACCO: Bank of Uganda',
    'Bank of Uganda',
    'Microfinance Deposit-Taking Institutions (Registered Societies) Regulations 2023',
    'Reported to apply above UGX 1.5bn voluntary savings and UGX 500m institutional capital. The SACCO union disputes this in court, so ask a lawyer if you are near these sizes.',
  ),
  LicenceItem(
    'Self-help group (VSLA) registration',
    'District Community Development Officer, reporting to UMRA',
    'UMRA Self-Help Group Guidelines, under the Tier 4 Act',
    'Savings groups register at the district, a lighter route than a licence. Ask your district office for the form.',
  ),
  LicenceItem(
    'Money lender licence (only if lending to the public)',
    'UMRA',
    'Tier 4 Microfinance Institutions and Money Lenders Act, 2016',
    'For lending as a business outside a member group. Compound interest is barred, and a loan agreement is required.',
  ),
];

const platformLicences = [
  LicenceItem(
    'Company registration and tax',
    'URSB and URA',
    'Companies Act; Income Tax Act',
    'Register the company that owns the app and get a TIN. Needed for every contract below.',
  ),
  LicenceItem(
    'Personal data registration',
    'Personal Data Protection Office (PDPO, under NITA-U)',
    'Data Protection and Privacy Act, 2019',
    'The app stores names, phones and money records, so register online with PDPO, renew every year, name a data protection officer, and keep a record of why data may sit outside Uganda. Do this first.',
  ),
  LicenceItem(
    'Written legal opinion: "are we a payment service?"',
    'Your lawyer, then Bank of Uganda if needed',
    'National Payment Systems Act, 2020',
    'A records-only app that never touches money should sit outside payment licences, but only a lawyer or Bank of Uganda can confirm this. Get it in writing.',
  ),
  LicenceItem(
    'App store financial declarations',
    'Google Play and Apple',
    'Store policies',
    'Stores can ask a finance app for proof of who you are and what you do. Keep the opinion and registrations ready.',
  ),
];

const futureLicences = [
  LicenceItem(
    'Payment system operator or payment service provider licence',
    'Bank of Uganda',
    'National Payment Systems Act, 2020; Regulations 2021',
    'Covers gateways, aggregators, integrators and e-money. Needed if the company collects, holds or routes money, for example one shared collection account. Lowest capital reported: UGX 100m (operator), UGX 250m (e-money issuer). Avoid it by keeping "groups use their own accounts".',
  ),
  LicenceItem(
    'NITA-U certification',
    'National Information Technology Authority',
    'NITA-U Certification Regulations',
    'Required before a Bank of Uganda application.',
  ),
  LicenceItem(
    'Accountable person registration',
    'Financial Intelligence Authority',
    'Anti-Money Laundering Act',
    'For those who transfer money or take deposits. Keep records for 10 years and report suspicious transactions.',
  ),
  LicenceItem(
    'SMS sender ID',
    'MTN, Airtel, through an SMS provider (UCC rules)',
    'UCC rules; Data Protection Act',
    'Only if you send SMS alerts. Registered with each network. Reported at about UGX 250,000 a month per ID.',
  ),
];
