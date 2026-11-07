/// Plain words for the terms people meet in the app. Shown by the (i) buttons.
class Term {
  final String title;
  final String text;
  const Term(this.title, this.text);
}

const glossary = <String, Term>{
  'shares': Term('Shares',
      'Money you put in at a fixed price, like buying small pieces of the group. At share-out you get back your shares plus your part of the profit.'),
  'savings': Term('Savings', 'Money you keep in the group. It is yours. It also decides how much you can borrow.'),
  'ledger': Term('Ledger',
      'The group\'s money book. Every shilling in or out is written here once and can never be edited or deleted. Mistakes are fixed with a new, visible correction.'),
  'double_entry': Term('Double-entry',
      'Every amount is written twice: where it came from and where it went. The two sides must always be equal. If they are not, something is wrong and the app shows it at once.'),
  'two_person': Term('Two-person check',
      'One person records a payment, a different person confirms it. Nobody can add money to the books alone, so honest mistakes and tricks are caught.'),
  'share_out': Term(
      'Share-out', 'At the end of a cycle the group pays every member back their savings plus their fair part of the profit from loan interest and fines.'),
  'emergency_fund':
      Term('Emergency fund', 'A small separate pot for members in trouble (illness, a funeral). It is not a loan. The group agrees who gets help.'),
  'loan_limit': Term('Loan limit', 'The most a member can borrow, as times their savings. With 3, someone with 100,000 saved can borrow up to 300,000.'),
  'quorum': Term('Quorum', 'How many members must be at a meeting for its decisions to count. 67% means two out of every three members.'),
  'arrears': Term('Arrears', 'Loan payments that are late. The longer they are late, the bigger the risk the money is not paid back.'),
  'audit_trail': Term('Audit trail',
      'A list of every action, who did it and when. Each line is sealed to the one before, so changing an old line breaks the seal and the tamper check shows it.'),
  'merchant_code': Term(
      'Merchant code', 'The number your group gets from MTN, Airtel or M-Pesa to receive payments. Members pay it directly. The app never holds the money.'),
  'verified_payment': Term('Checked online payment',
      'The payment company tells our server it was paid, then our server asks them again. Only then does it enter the books. Nobody types the transaction ID.'),
  'cycle': Term('Cycle', 'One saving period, often 9 to 12 months, that ends with a share-out. Then a new cycle starts.'),
};
