// lib/screens/select_outfit_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'daily_outfit_screen.dart';

/// Obrazovka, kde si používateľ vyberie, na čo chce outfit:
/// - na dnes
/// - na zajtra
/// - na dnešnú udalosť (ak existuje v kalendári)
/// - na zajtrajšiu udalosť (ak existuje v kalendári)
class SelectOutfitScreen extends StatefulWidget {
  const SelectOutfitScreen({Key? key}) : super(key: key);

  @override
  State<SelectOutfitScreen> createState() => _SelectOutfitScreenState();
}

class _SelectOutfitScreenState extends State<SelectOutfitScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoadingEvents = true;

  // dnes a zajtra môžeme mať VIAC udalostí
  List<Map<String, dynamic>> _todayEvents = [];
  List<Map<String, dynamic>> _tomorrowEvents = [];

  @override
  void initState() {
    super.initState();
    _loadEventsFromCalendar();
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _loadEventsFromCalendar() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingEvents = false;
      });
      return;
    }

    final eventsRef = _firestore
        .collection('calendarEvents')
        .doc(user.uid)
        .collection('events');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final todayStr = _formatDate(today);
    final tomorrowStr = _formatDate(tomorrow);

    try {
      // 🔹 načítame VŠETKY dnešné udalosti
      final todaySnap =
      await eventsRef.where('date', isEqualTo: todayStr).get();

      // 🔹 načítame VŠETKY zajtrajšie udalosti
      final tomorrowSnap =
      await eventsRef.where('date', isEqualTo: tomorrowStr).get();

      List<Map<String, dynamic>> _fromSnapshot(QuerySnapshot snap) {
        return snap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            ...data,
          };
        }).toList();
      }

      final todayEvents = _fromSnapshot(todaySnap);
      final tomorrowEvents = _fromSnapshot(tomorrowSnap);

      // pokusne zoradíme podľa startTime (formát "HH:MM" – stringové poradie funguje)
      int _compareByStartTime(Map<String, dynamic> a, Map<String, dynamic> b) {
        final t1 = (a['startTime'] as String? ?? '');
        final t2 = (b['startTime'] as String? ?? '');
        return t1.compareTo(t2);
      }

      todayEvents.sort(_compareByStartTime);
      tomorrowEvents.sort(_compareByStartTime);

      setState(() {
        _todayEvents = todayEvents;
        _tomorrowEvents = tomorrowEvents;
        _isLoadingEvents = false;
      });
    } catch (e) {
      debugPrint('Chyba pri načítavaní udalostí pre výber outfitu: $e');
      setState(() {
        _isLoadingEvents = false;
      });
    }
  }

  String _buildEventSubtitle(Map<String, dynamic> event) {
    final title = (event['title'] as String? ?? '').trim();
    final location = (event['location'] as String? ?? '').trim();
    final startTime = (event['startTime'] as String? ?? '').trim();
    final endTime = (event['endTime'] as String? ?? '').trim();

    final parts = <String>[];

    if (title.isNotEmpty) parts.add(title);
    if (location.isNotEmpty) parts.add(location);
    if (startTime.isNotEmpty || endTime.isNotEmpty) {
      final buf = StringBuffer();
      if (startTime.isNotEmpty) buf.write(startTime);
      if (endTime.isNotEmpty) buf.write(' – $endTime');
      parts.add(buf.toString());
    }

    return parts.join(' • ');
  }

  Future<void> _openOutfitForDay({required bool isTomorrow}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DailyOutfitScreen(
          isTomorrow: isTomorrow,
        ),
      ),
    );
  }

  Future<void> _openOutfitForEvent({
    required bool isTomorrow,
    required Map<String, dynamic> event,
    required DateTime date,
  }) async {
    final eventData = {
      'title': (event['title'] as String? ?? '').trim(),
      'location': (event['location'] as String? ?? '').trim(),
      'startTime': (event['startTime'] as String? ?? '').trim(),
      'endTime': (event['endTime'] as String? ?? '').trim(),
      'date': _formatDate(date),
    };

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DailyOutfitScreen(
          isTomorrow: isTomorrow,
          eventData: eventData,
        ),
      ),
    );
  }

  /// Spodný sheet, kde si vyberieš, na ktorú udalosť chceš outfit
  Future<void> _selectEventFromList({
    required List<Map<String, dynamic>> events,
    required bool isTomorrow,
  }) async {
    if (events.isEmpty) return;

    final now = DateTime.now();
    final baseDate = DateTime(now.year, now.month, now.day);
    final date = isTomorrow
        ? baseDate.add(const Duration(days: 1))
        : baseDate;

    // ak je iba 1 udalosť, netreba sheet, rovno otvoríme outfit
    if (events.length == 1) {
      await _openOutfitForEvent(
        isTomorrow: isTomorrow,
        event: events.first,
        date: date,
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isTomorrow
                      ? 'Vyber si zajtrajšiu udalosť'
                      : 'Vyber si dnešnú udalosť',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final title =
                      (event['title'] as String? ?? 'Udalosť').trim();
                      final subtitle = _buildEventSubtitle(event);

                      return ListTile(
                        leading: const Icon(Icons.event),
                        title: Text(title),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        onTap: () async {
                          Navigator.pop(context);
                          await _openOutfitForEvent(
                            isTomorrow: isTomorrow,
                            event: event,
                            date: date,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTodayEvents = _todayEvents.isNotEmpty;
    final hasTomorrowEvents = _tomorrowEvents.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vybrať outfit'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Vyber si, na čo chceš outfit:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Outfit na dnes
          _buildOptionCard(
            icon: Icons.today_outlined,
            title: 'Outfit na dnes',
            subtitle:
            'Bežný denný outfit na dnešok podľa počasia a tvojho šatníka.',
            onTap: () => _openOutfitForDay(isTomorrow: false),
          ),
          const SizedBox(height: 12),

          // Outfit na zajtra
          _buildOptionCard(
            icon: Icons.calendar_today_outlined,
            title: 'Outfit na zajtra',
            subtitle: 'Priprav sa dopredu – outfit na zajtra podľa počasia.',
            onTap: () => _openOutfitForDay(isTomorrow: true),
          ),

          const SizedBox(height: 24),

          if (_isLoadingEvents)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!hasTodayEvents && !hasTomorrowEvents)
            const Text(
              'V kalendári zatiaľ nemáš žiadne udalosti na dnes ani zajtra.',
              style: TextStyle(fontSize: 14),
            )
          else ...[
              const Text(
                'Udalosti z kalendára:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              if (hasTodayEvents) ...[
                _buildOptionCard(
                  icon: Icons.event,
                  title: 'Outfit na dnešnú udalosť',
                  subtitle: _todayEvents.length == 1
                      ? _buildEventSubtitle(_todayEvents.first)
                      : '${_todayEvents.length} udalosti – klikni a vyber konkrétnu',
                  onTap: () => _selectEventFromList(
                    events: _todayEvents,
                    isTomorrow: false,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (hasTomorrowEvents)
                _buildOptionCard(
                  icon: Icons.event_available_outlined,
                  title: 'Outfit na zajtrajšiu udalosť',
                  subtitle: _tomorrowEvents.length == 1
                      ? _buildEventSubtitle(_tomorrowEvents.first)
                      : '${_tomorrowEvents.length} udalosti – klikni a vyber konkrétnu',
                  onTap: () => _selectEventFromList(
                    events: _tomorrowEvents,
                    isTomorrow: true,
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
