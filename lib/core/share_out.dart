/// Largest remainder share-out. The server runs the same rule on real money;
/// this copy powers the worked examples on screen and is checked by the same tests.
class ShareOutInput {
  final String id;
  final String name;
  final int savings;
  const ShareOutInput(this.id, this.name, this.savings);
}

class ShareOutRow {
  final String id;
  final String name;
  final int savings;
  final int payout;
  final bool bonus;
  const ShareOutRow(this.id, this.name, this.savings, this.payout, this.bonus);
  int get profit => payout - savings;
}

class ShareOut {
  static List<ShareOutRow> calculate(int pool, List<ShareOutInput> members) {
    final total = members.fold<int>(0, (a, m) => a + m.savings);
    if (members.isEmpty || pool <= 0 || total <= 0) return const [];
    final base = <String, int>{};
    final rem = <String, BigInt>{};
    final bigPool = BigInt.from(pool);
    final bigTotal = BigInt.from(total);
    var sum = 0;
    for (final m in members) {
      final product = bigPool * BigInt.from(m.savings);
      final b = (product ~/ bigTotal).toInt();
      base[m.id] = b;
      rem[m.id] = product.remainder(bigTotal);
      sum += b;
    }
    var surplus = pool - sum;
    final order = [...members]
      ..sort((a, b) {
        final c = rem[b.id]!.compareTo(rem[a.id]!);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final bonus = <String>{};
    for (final m in order) {
      if (surplus <= 0) break;
      bonus.add(m.id);
      surplus--;
    }
    return members.map((m) => ShareOutRow(m.id, m.name, m.savings, base[m.id]! + (bonus.contains(m.id) ? 1 : 0), bonus.contains(m.id))).toList();
  }
}
