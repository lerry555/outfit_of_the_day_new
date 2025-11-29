// lib/screens/calendar_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';

/// Hlavná obrazovka kalendára udalostí.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime(
      _focusedDay.year,
      _focusedDay.month,
      _focusedDay.day,
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String? eventId = event['id'] as String?;
    if (eventId == null) return;

    try {
      await _firestore
          .collection('calendarEvents')
          .doc(user.uid)
          .collection('events')
          .doc(eventId)
          .delete();
    } catch (e) {
      debugPrint('Chyba pri mazaní udalosti: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa zmazať udalosť. Skús znova.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('Musíš byť prihlásený.'),
        ),
      );
    }

    final eventsRef = _firestore
        .collection('calendarEvents')
        .doc(user.uid)
        .collection('events');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalendár udalostí'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: eventsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Chyba pri načítavaní kalendára.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data!.docs;

          // dátum -> zoznam udalostí
          final Map<DateTime, List<Map<String, dynamic>>> eventsByDay = {};

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final dateStr = data['date'] as String?;
            if (dateStr == null) continue;

            DateTime date;
            try {
              date = DateTime.parse(dateStr);
            } catch (_) {
              continue;
            }

            final dayKey = _dateOnly(date);
            eventsByDay.putIfAbsent(dayKey, () => []);
            eventsByDay[dayKey]!.add({
              'id': doc.id,
              ...data,
            });
          }

          final selectedDayKey =
          _selectedDay != null ? _dateOnly(_selectedDay!) : null;
          final selectedEvents =
          (selectedDayKey != null && eventsByDay.containsKey(selectedDayKey))
              ? eventsByDay[selectedDayKey]!
              : <Map<String, dynamic>>[];

          return Column(
            children: [
              TableCalendar<Map<String, dynamic>>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2100, 12, 31),
                focusedDay: _focusedDay,
                locale: 'sk_SK',
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) =>
                    isSameDay(_selectedDay, day),
                eventLoader: (day) {
                  final key = _dateOnly(day);
                  return eventsByDay[key] ?? [];
                },
                startingDayOfWeek: StartingDayOfWeek.monday,
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = _dateOnly(selectedDay);
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
                // guličky pri dňoch s udalosťou
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markerDecoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    shape: BoxShape.circle,
                  ),
                  markersAlignment: Alignment.bottomCenter,
                  markersMaxCount: 3,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedDay == null
                            ? 'Vyber deň v kalendári'
                            : 'Udalosti: ${_formatDate(_selectedDay!)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _selectedDay == null
                          ? null
                          : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddCalendarEventScreen(
                                  initialDate: _selectedDay!,
                                ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Pridať udalosť'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: selectedEvents.isEmpty
                    ? const Center(
                  child: Text(
                    'Na tento deň nemáš žiadnu udalosť.',
                  ),
                )
                    : ListView.builder(
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    final title =
                        (event['title'] as String?) ?? 'Udalosť';
                    final type =
                        (event['type'] as String?) ?? '';
                    final location =
                        (event['location'] as String?) ?? '';
                    final timeFrom =
                        (event['startTime'] as String?) ?? '';
                    final timeTo =
                        (event['endTime'] as String?) ?? '';

                    final subtitleParts = <String>[];

                    if (type.isNotEmpty && type != title) {
                      subtitleParts.add(type);
                    }
                    if (location.isNotEmpty) subtitleParts.add(location);
                    if (timeFrom.isNotEmpty || timeTo.isNotEmpty) {
                      final buf = StringBuffer();
                      if (timeFrom.isNotEmpty) buf.write(timeFrom);
                      if (timeTo.isNotEmpty) buf.write(' – $timeTo');
                      subtitleParts.add(buf.toString());
                    }

                    return ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(title),
                      subtitle: subtitleParts.isEmpty
                          ? null
                          : Text(subtitleParts.join(' • ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          final confirmed =
                              await showDialog<bool>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text(
                                        'Zmazať udalosť?'),
                                    content: Text(
                                      'Naozaj chceš zmazať udalosť "$title"?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(
                                              context, false);
                                        },
                                        child:
                                        const Text('Nie'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(
                                              context, true);
                                        },
                                        child:
                                        const Text('Áno'),
                                      ),
                                    ],
                                  );
                                },
                              ) ??
                                  false;

                          if (confirmed) {
                            await _deleteEvent(event);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// odstránenie diakritiky pre fulltext vyhľadávanie typov udalostí
String removeDiacritics(String text) {
  const withDia = 'áäčďéíĺľňóôŕřšťúýžÁÄČĎÉÍĹĽŇÓÔŔŘŠŤÚÝŽ';
  const withoutDia = 'aacdeillnoorrstuyzAACDEILLNOORRSTUYZ';

  String out = '';
  for (int i = 0; i < text.length; i++) {
    final index = withDia.indexOf(text[i]);
    if (index >= 0) {
      out += withoutDia[index];
    } else {
      out += text[i];
    }
  }
  return out.toLowerCase();
}

/// Obrazovka na pridanie udalosti
class AddCalendarEventScreen extends StatefulWidget {
  final DateTime initialDate;

  const AddCalendarEventScreen({
    Key? key,
    required this.initialDate,
  }) : super(key: key);

  @override
  State<AddCalendarEventScreen> createState() =>
      _AddCalendarEventScreenState();
}

class _AddCalendarEventScreenState extends State<AddCalendarEventScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _eventTitleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();

  // Focus node pre miesto – aby sme vedeli, kedy zobrazovať návrhy
  final FocusNode _locationFocusNode = FocusNode();

  // návrhy miest z API
  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _isLoadingLocations = false;
  Timer? _locationDebounce;
  Map<String, dynamic>? _selectedLocation; // ak vyberieš z listu, uložíme aj lat/lon

  final List<String> _baseEventTypeOptions = const [
    'Pracovné stretnutie',
    'Biznis meeting',
    'Pohovor',
    'Prezentácia',
    'Konferencia',
    'Firemná akcia',
    'Teambuilding',
    'Party',
    'Oslava',
    'Narodeniny',
    'Silvester',
    'Grilovačka',
    'Výročie',
    'Rande',
    'Valentín',
    'Svadba',
    'Zasnúbenie',
    'Rozlúčka so slobodou',
    'Skúška',
    'Prednáška',
    'Seminár',
    'Absolventská',
    'Kino',
    'Divadlo',
    'Koncert',
    'Festival',
    'Opera',
    'Galéria',
    'Posilka',
    'Beh',
    'Turistika',
    'Plávanie',
    'Lyžovanie',
    'Športová akcia',
  ];

  List<String> _userEventTypeOptions = [];
  String _eventTitleText = '';

  List<String> get _allEventTypeOptions {
    final set = <String>{};
    set.addAll(_baseEventTypeOptions);
    set.addAll(_userEventTypeOptions);
    final list = set.toList();
    list.sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadUserEventTypes();
  }

  @override
  void dispose() {
    _eventTitleController.dispose();
    _locationController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _locationFocusNode.dispose();
    _locationDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUserEventTypes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc =
      await _firestore.collection('calendarEvents').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['eventTypes'] is List) {
          final list = (data['eventTypes'] as List)
              .whereType<String>()
              .toList();
          setState(() {
            _userEventTypeOptions = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Chyba pri načítaní vlastných typov udalostí: $e');
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// MIUI-like výber času – 2 kolieska (hodiny / minúty)
  Future<void> _pickTime({required bool isStart}) async {
    final controller = isStart ? _startTimeController : _endTimeController;

    final now = TimeOfDay.now();
    int initialHour = now.hour;
    int initialMinute = now.minute;

    if (controller.text.isNotEmpty && controller.text.contains(':')) {
      final parts = controller.text.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          initialHour = h;
          initialMinute = m;
        }
      }
    }

    int tempHour = initialHour;
    int tempMinute = initialMinute;

    final hourController =
    FixedExtentScrollController(initialItem: initialHour);
    final minuteController =
    FixedExtentScrollController(initialItem: initialMinute);

    bool confirmed = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final width = MediaQuery.of(context).size.width;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            height: 340,
            width: width * 0.85,
            child: Column(
              children: [
                // horný riadok s tlačidlami
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('Zrušiť'),
                      ),
                      TextButton(
                        onPressed: () {
                          confirmed = true;
                          Navigator.pop(context);
                        },
                        child: const Text('Hotovo'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0),

                // 2 kolieska: hodiny a minúty
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: hourController,
                          itemExtent: 40,
                          useMagnifier: true,
                          magnification: 1.2,
                          onSelectedItemChanged: (index) {
                            tempHour = index;
                          },
                          children: List.generate(
                            24,
                                (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: minuteController,
                          itemExtent: 40,
                          useMagnifier: true,
                          magnification: 1.2,
                          onSelectedItemChanged: (index) {
                            tempMinute = index;
                          },
                          children: List.generate(
                            60,
                                (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed) {
      final hh = tempHour.toString().padLeft(2, '0');
      final mm = tempMinute.toString().padLeft(2, '0');
      setState(() {
        controller.text = '$hh:$mm';
      });
    }
  }

  /// Keď používateľ píše miesto, s oneskorením 0.4s zavoláme API a načítame návrhy.
  void _onLocationChanged(String value) {
    _selectedLocation = null; // keď začneš písať, zabudneme starý výber

    _locationDebounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _locationSuggestions = [];
      });
      return;
    }

    _locationDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchLocationSuggestions(value.trim());
    });
  }

  Future<void> _fetchLocationSuggestions(String query) async {
    setState(() {
      _isLoadingLocations = true;
    });

    try {
      // Nominatim – OpenStreetMap vyhľadávanie (celý svet)
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=$query&format=json&addressdetails=1&limit=5',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'outfit-of-the-day-app', // Nominatim to vyžaduje
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        final suggestions = body.map<Map<String, dynamic>>((item) {
          final map = item as Map<String, dynamic>;
          return {
            'displayName': map['display_name'] as String? ?? '',
            'lat': map['lat'],
            'lon': map['lon'],
          };
        }).where((s) => (s['displayName'] as String).isNotEmpty).toList();

        if (!mounted) return;
        setState(() {
          _locationSuggestions = suggestions;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _locationSuggestions = [];
        });
      }
    } catch (e) {
      debugPrint('Chyba pri vyhľadávaní miesta: $e');
      if (!mounted) return;
      setState(() {
        _locationSuggestions = [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingLocations = false;
      });
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final dateStr = _formatDate(widget.initialDate);
    final trimmedTitle = _eventTitleText.trim();

    try {
      final userDoc = _firestore.collection('calendarEvents').doc(user.uid);
      final eventsRef = userDoc.collection('events');

      await eventsRef.add({
        'date': dateStr,
        'title': trimmedTitle,
        'type': trimmedTitle,
        'location': _locationController.text.trim(),
        'locationLat': _selectedLocation?['lat'],
        'locationLon': _selectedLocation?['lon'],
        'startTime': _startTimeController.text.trim(),
        'endTime': _endTimeController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (trimmedTitle.isNotEmpty &&
          !_baseEventTypeOptions.contains(trimmedTitle)) {
        await userDoc.set(
          {
            'eventTypes': FieldValue.arrayUnion([trimmedTitle]),
          },
          SetOptions(merge: true),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Chyba pri ukladaní udalosti: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa uložiť udalosť. Skús znova.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _formatDate(widget.initialDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pridať udalosť'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'Dátum: $dateText',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // Názov / typ udalosti (autocomplete)
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final query = removeDiacritics(textEditingValue.text);

                  if (query.isEmpty) {
                    return _allEventTypeOptions;
                  }

                  return _allEventTypeOptions.where((option) {
                    final normalizedOption =
                    removeDiacritics(option);
                    return normalizedOption.contains(query);
                  });
                },
                onSelected: (String selection) {
                  setState(() {
                    _eventTitleText = selection;
                    _eventTitleController.text = selection;
                  });
                },
                fieldViewBuilder: (context, textEditingController, focusNode,
                    onFieldSubmitted) {
                  _eventTitleController.value = textEditingController.value;

                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Názov / typ udalosti',
                      hintText:
                      'Napr. Svadba, Koncert, Rande, večera v reštaurácii...',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _eventTitleText = value;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Zadaj názov alebo typ udalosti';
                      }
                      return null;
                    },
                  );
                },
                optionsViewBuilder:
                    (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      child: SizedBox(
                        height: 200,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option),
                              onTap: () {
                                onSelected(option);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Miesto s autocomplete cez OpenStreetMap
              TextFormField(
                controller: _locationController,
                focusNode: _locationFocusNode,
                decoration: InputDecoration(
                  labelText: 'Miesto / lokalita',
                  hintText: 'Začni písať: napr. Necpaly, Praha...',
                  suffixIcon: _isLoadingLocations
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                      : const Icon(Icons.place_outlined),
                ),
                onChanged: _onLocationChanged,
              ),
              if (_locationFocusNode.hasFocus &&
                  _locationSuggestions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _locationSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _locationSuggestions[index];
                      final String displayName =
                      suggestion['displayName'] as String;
                      return ListTile(
                        title: Text(
                          displayName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: () {
                          setState(() {
                            _locationController.text = displayName;
                            _selectedLocation = suggestion;
                            _locationSuggestions = [];
                            _locationFocusNode.unfocus();
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Čas od
              TextFormField(
                controller: _startTimeController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Začiatok (čas)',
                  hintText: 'Vyber čas začiatku',
                  suffixIcon: Icon(Icons.access_time),
                ),
                onTap: () => _pickTime(isStart: true),
              ),
              const SizedBox(height: 12),

              // Čas do
              TextFormField(
                controller: _endTimeController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Koniec (čas)',
                  hintText: 'Vyber čas konca',
                  suffixIcon: Icon(Icons.access_time),
                ),
                onTap: () => _pickTime(isStart: false),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _saveEvent,
                child: const Text('Uložiť udalosť'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
