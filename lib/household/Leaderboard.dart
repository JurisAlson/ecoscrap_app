import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final Color primaryColor = const Color(0xFF1FA9A7);

  DateTime selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  String get monthId {
    final month = selectedMonth.month.toString().padLeft(2, '0');
    return '${selectedMonth.year}-$month';
  }

  String _monthName(int month) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return months[month - 1];
  }

  void _previousMonth() {
    setState(() {
      selectedMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      selectedMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month + 1,
      );
    });
  }

  Stream<List<_LeaderboardUser>> _leaderboardStream() {
    return FirebaseFirestore.instance
        .collection('leaderboards')
        .doc(monthId)
        .collection('users')
        .snapshots()
        .map((snap) {
      final users = snap.docs.map((doc) {
        final data = doc.data();

        return _LeaderboardUser(
          uid: doc.id,
          name: (data['name'] ?? 'Household User').toString(),
          points: _toInt(data['points']),
          transactions: _toInt(data['transactions']),
          pickups: _toInt(data['pickups']),
          dropoffs: _toInt(data['dropoffs']),
          totalKg: _toInt(data['totalKg']),
        );
      }).toList();

      users.sort((a, b) {
        final points = b.points.compareTo(a.points);
        if (points != 0) return points;

        final transactions = b.transactions.compareTo(a.transactions);
        if (transactions != 0) return transactions;

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return users;
    });
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<List<_LeaderboardUser>>(
      stream: _leaderboardStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                "Failed to load leaderboard:\n${snap.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        final users = snap.data ?? [];
        final topFive = users.take(5).toList();
        final activeUsers = users.where((u) => u.transactions > 0).toList();

        final topContributor =
            activeUsers.isEmpty ? null : activeUsers.first;

        final myIndex = users.indexWhere((u) => u.uid == currentUid);
        final myRank = myIndex == -1 ? null : myIndex + 1;
        final myData = myIndex == -1 ? null : users[myIndex];

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Leaderboard",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Monthly trash contributor ranking.",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 16),

              _monthSelector(),

              const SizedBox(height: 16),

              if (topContributor == null)
                _emptyTopContributorCard()
              else
                _topContributorCard(topContributor),

              const SizedBox(height: 18),

              const Text(
                "Top 5 Users",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),

              if (topFive.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 50, bottom: 50),
                  child: Center(
                    child: Text(
                      "No leaderboard records for this month yet.",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else
                ...List.generate(topFive.length, (i) {
                  final user = topFive[i];

                  return _rankCard(
                    rank: i + 1,
                    user: user,
                    highlight: user.uid == currentUid,
                  );
                }),

              const SizedBox(height: 20),

              _myRankCard(myRank, myData),
            ],
          ),
        );
      },
    );
  }

  Widget _monthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _previousMonth,
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Expanded(
            child: Center(
              child: Text(
                "${_monthName(selectedMonth.month)} ${selectedMonth.year}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _topContributorCard(_LeaderboardUser user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withOpacity(0.85),
            Colors.green.withOpacity(0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.white, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Top Trash Contributor",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  user.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  "${user.points} pts • ${user.totalKg} kg • ${user.transactions} transaction(s)",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTopContributorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: const Text(
        "No top contributor yet for this month.",
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _myRankCard(int? rank, _LeaderboardUser? user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your Current Place",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rank == null || user == null
                ? "You are not ranked for this month yet."
                : "Rank #$rank • ${user.points} pts",
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 6),
            Text(
              "${user.transactions} transaction(s) • ${user.totalKg} kg",
              style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rankCard({
    required int rank,
    required _LeaderboardUser user,
    required bool highlight,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? primaryColor.withOpacity(0.14)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight
              ? primaryColor.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: primaryColor.withOpacity(0.18),
            child: Text(
              "$rank",
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${user.transactions} transaction(s) • ${user.pickups} pickup • ${user.dropoffs} drop-off • ${user.totalKg} kg",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${user.points} pts",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardUser {
  final String uid;
  final String name;
  final int points;
  final int transactions;
  final int pickups;
  final int dropoffs;
  final int totalKg;

  _LeaderboardUser({
    required this.uid,
    required this.name,
    required this.points,
    required this.transactions,
    required this.pickups,
    required this.dropoffs,
    required this.totalKg,
  });
}