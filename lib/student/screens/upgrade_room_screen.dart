import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static data from hostel_renew_fee table (final, approved by admin)
// ─────────────────────────────────────────────────────────────────────────────
class _Room {
  final String id;
  final String name;
  final double hostelFee;
  final double foodFee;
  final double totalFee;
  final String description;

  const _Room({
    required this.id,
    required this.name,
    required this.hostelFee,
    required this.foodFee,
    required this.totalFee,
    required this.description,
  });

  double get monthlyAmount => hostelFee / 12;
}

const _kRooms = [
  _Room(id: 'DORM 38 - Non AC',             name: 'DORM 38 - Non AC',             hostelFee: 25000, foodFee: 50000, totalFee: 75000,  description: 'Non AC Dormitory (38 beds)'),
  _Room(id: 'DORM 20 - Non AC',             name: 'DORM 20 - Non AC',             hostelFee: 30000, foodFee: 50000, totalFee: 80000,  description: 'Non AC Dormitory (20 beds)'),
  _Room(id: 'DORM 25 - Non AC',             name: 'DORM 25 - Non AC',             hostelFee: 30000, foodFee: 50000, totalFee: 80000,  description: 'Non AC Dormitory (25 beds)'),
  _Room(id: 'DORM 36 - AC',                 name: 'DORM 36 - AC',                 hostelFee: 30000, foodFee: 50000, totalFee: 80000,  description: 'AC Dormitory (36 beds)'),
  _Room(id: '7 IN 1 Non AC',                name: '7 IN 1 Non AC',                hostelFee: 31000, foodFee: 50000, totalFee: 81000,  description: 'Non AC sharing (7 students)'),
  _Room(id: 'DORM 10 - Non AC',             name: 'DORM 10 - Non AC',             hostelFee: 31000, foodFee: 50000, totalFee: 81000,  description: 'Non AC Dormitory (10 beds)'),
  _Room(id: '6 IN 1 Non AC',                name: '6 IN 1 Non AC',                hostelFee: 32000, foodFee: 50000, totalFee: 82000,  description: 'Non AC sharing (6 students)'),
  _Room(id: '5 IN 1 Non AC',                name: '5 IN 1 Non AC',                hostelFee: 33000, foodFee: 50000, totalFee: 83000,  description: 'Non AC sharing (5 students)'),
  _Room(id: '4 IN 1 Non AC',                name: '4 IN 1 Non AC',                hostelFee: 34000, foodFee: 50000, totalFee: 84000,  description: 'Non AC sharing (4 students)'),
  _Room(id: '3 IN 1 Non AC',                name: '3 IN 1 Non AC',                hostelFee: 35000, foodFee: 50000, totalFee: 85000,  description: 'Non AC sharing (3 students)'),
  _Room(id: 'Double Non AC',                name: 'Double Non AC',                hostelFee: 40000, foodFee: 50000, totalFee: 90000,  description: 'Non AC Double Room'),
  _Room(id: 'DORM 12 - AC',                 name: 'DORM 12 - AC',                 hostelFee: 45000, foodFee: 50000, totalFee: 95000,  description: 'AC Dormitory (12 beds)'),
  _Room(id: 'Double Semi Deluxe Non AC',    name: 'Double Semi Deluxe Non AC',    hostelFee: 50000, foodFee: 50000, totalFee: 100000, description: 'Semi Deluxe Non AC Double Room'),
  _Room(id: 'Single Room Non AC',           name: 'Single Room Non AC',           hostelFee: 50000, foodFee: 50000, totalFee: 100000, description: 'Single Non AC Room'),
  _Room(id: 'Single Bath Attached Non AC',  name: 'Single Bath Attached Non AC',  hostelFee: 55000, foodFee: 50000, totalFee: 105000, description: 'Single Non AC with Bath Attached'),
  _Room(id: '8 IN 1 AC',                    name: '8 IN 1 AC',                    hostelFee: 55000, foodFee: 50000, totalFee: 105000, description: 'AC sharing (8 students)'),
  _Room(id: '8 IN 1 Bath Attached AC',      name: '8 IN 1 Bath Attached AC',      hostelFee: 60000, foodFee: 50000, totalFee: 110000, description: 'AC with Bath Attached (8 students)'),
  _Room(id: '6 IN 1 AC',                    name: '6 IN 1 AC',                    hostelFee: 60000, foodFee: 50000, totalFee: 110000, description: 'AC sharing (6 students)'),
  _Room(id: '6 IN 1 Bath Attached AC',      name: '6 IN 1 Bath Attached AC',      hostelFee: 65000, foodFee: 50000, totalFee: 115000, description: 'AC with Bath Attached (6 students)'),
  _Room(id: '5 IN 1 AC',                    name: '5 IN 1 AC',                    hostelFee: 65000, foodFee: 50000, totalFee: 115000, description: 'AC sharing (5 students)'),
  _Room(id: '4 IN 1 AC',                    name: '4 IN 1 AC',                    hostelFee: 70000, foodFee: 50000, totalFee: 120000, description: 'AC sharing (4 students)'),
  _Room(id: 'Single Room A/C',              name: 'Single Room A/C',              hostelFee: 70000, foodFee: 50000, totalFee: 120000, description: 'Single AC Room'),
  _Room(id: '4 IN 1 Bath Attached AC',      name: '4 IN 1 Bath Attached AC',      hostelFee: 75000, foodFee: 50000, totalFee: 125000, description: 'AC with Bath Attached (4 students)'),
  _Room(id: '3 IN 1 AC',                    name: '3 IN 1 AC',                    hostelFee: 75000, foodFee: 50000, totalFee: 125000, description: 'AC sharing (3 students)'),
  _Room(id: 'Single Suit Room Bath Attached Non AC', name: 'Single Suit Room Bath Attached Non AC', hostelFee: 80000, foodFee: 50000, totalFee: 130000, description: 'Single Suite Non AC with Bath Attached'),
  _Room(id: '4 IN 1 B and T Attached AC',   name: '4 IN 1 B and T Attached AC',   hostelFee: 80000, foodFee: 50000, totalFee: 130000, description: 'AC with Bath & Toilet Attached (4 students)'),
  _Room(id: 'Semi Deluxe 4 IN 1 Bath Attached AC', name: 'Semi Deluxe 4 IN 1 Bath Attached AC', hostelFee: 90000, foodFee: 50000, totalFee: 140000, description: 'Semi Deluxe AC with Bath Attached (4 students)'),
  _Room(id: 'Single Bath Attached A/C',     name: 'Single Bath Attached A/C',     hostelFee: 90000, foodFee: 50000, totalFee: 140000, description: 'Single AC with Bath Attached'),
  _Room(id: 'Super Deluxe 4 IN 1 Bath Attached AC', name: 'Super Deluxe 4 IN 1 Bath Attached AC', hostelFee: 95000, foodFee: 50000, totalFee: 145000, description: 'Super Deluxe AC with Bath Attached (4 students)'),
  _Room(id: 'Double AC',                    name: 'Double AC',                    hostelFee: 100000, foodFee: 50000, totalFee: 150000, description: 'AC Double Room'),
  _Room(id: '3 IN 1 Bath Attached AC',      name: '3 IN 1 Bath Attached AC',      hostelFee: 100000, foodFee: 50000, totalFee: 150000, description: 'AC with Bath Attached (3 students)'),
  _Room(id: 'Single Bath Attached Deluxe AC', name: 'Single Bath Attached Deluxe AC', hostelFee: 110000, foodFee: 50000, totalFee: 160000, description: 'Single Deluxe AC with Bath Attached'),
  _Room(id: 'Super Deluxe 3 IN 1 Bath Attached AC', name: 'Super Deluxe 3 IN 1 Bath Attached AC', hostelFee: 110000, foodFee: 50000, totalFee: 160000, description: 'Super Deluxe AC with Bath Attached (3 students)'),
  _Room(id: 'Double Super Deluxe Bath Attached AC', name: 'Double Super Deluxe Bath Attached AC', hostelFee: 120000, foodFee: 50000, totalFee: 170000, description: 'Super Deluxe AC with Bath (2 students)'),
  _Room(id: 'Single Bath Attached Semi Deluxe AC', name: 'Single Bath Attached Semi Deluxe AC', hostelFee: 150000, foodFee: 50000, totalFee: 200000, description: 'Single Semi Deluxe AC with Bath Attached'),
  _Room(id: 'Double Ultra Super Deluxe Bath Attached AC', name: 'Double Ultra Super Deluxe Bath Attached AC', hostelFee: 150000, foodFee: 50000, totalFee: 200000, description: 'Ultra Super Deluxe AC with Bath (2 students)'),
  _Room(id: 'Single Bath Attached Super Deluxe AC', name: 'Single Bath Attached Super Deluxe AC', hostelFee: 160000, foodFee: 50000, totalFee: 210000, description: 'Single Super Deluxe AC with Bath Attached'),
  _Room(id: 'Single Bath Attached Ultra Super Deluxe AC', name: 'Single Bath Attached Ultra Super Deluxe AC', hostelFee: 200000, foodFee: 50000, totalFee: 250000, description: 'Single Ultra Super Deluxe AC with Bath Attached'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class UpgradeRoomScreen extends StatelessWidget {
  final String currentRoomTypeId;
  // username kept for API compatibility if needed later
  final String username;

  const UpgradeRoomScreen({
    super.key,
    required this.currentRoomTypeId,
    this.username = '',
  });

  static const _navy = Color(0xFF1A2744);
  static const _gold = Color(0xFFD4AF37);

  bool _isCurrent(_Room r) {
    final a = r.id.trim().toLowerCase();
    final b = currentRoomTypeId.trim().toLowerCase();
    if (a == b) return true;
    // fuzzy: e.g. "8-sharing" vs "8 IN 1 Non AC"
    if (a.contains(b) || b.contains(a)) return true;
    return false;
  }

  String _rupees(double v) {
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    return '₹${fmt.format(v.round())}';
  }

  Widget _buildCard(BuildContext context, _Room room) {
    final isCurrent = _isCurrent(room);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFFFFFBEE) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? _gold : const Color(0xFFEEEEEE),
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [BoxShadow(color: _gold.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: name + Current badge ──────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? _navy : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        room.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 12),
            // ── Fee row ─────────────────────────────────────────────────
            Row(
              children: [
                // Hostel fee chip
                _feeChip('Hostel', room.hostelFee),
                const Spacer(),
                // Total + monthly
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _rupees(room.hostelFee),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? _gold : _gold,
                      ),
                    ),
                    Text(
                      'per year',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                    Text(
                      '~${_rupees(room.monthlyAmount)} / month',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _feeChip(String label, double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500)),
          Text(
            '₹${amount.toInt()}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sort: current room at top, rest in original order
    final sorted = [..._kRooms];
    final idx = sorted.indexWhere(_isCurrent);
    if (idx > 0) {
      final curr = sorted.removeAt(idx);
      sorted.insert(0, curr);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
          ),
        ),
        title: const Text(
          'Upgrade Room',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Lato',
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Info banner ───────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: _navy,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: const Text(
              'Compare room fees and decide if you want to upgrade. '
              'Use the "Room Change" button in the Renew screen to submit a request.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
          ),
          // ── Legend ────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(width: 12, height: 12,
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEE),
                        border: Border.all(color: _gold, width: 1.5),
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                const Text('Your current room', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const Spacer(),
                Text('${_kRooms.length} room types', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ── Room list ─────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
              physics: const BouncingScrollPhysics(),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) => _buildCard(ctx, sorted[i]),
            ),
          ),
        ],
      ),
    );
  }
}
