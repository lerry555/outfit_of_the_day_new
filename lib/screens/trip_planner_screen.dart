// lib/screens/trip_planner_screen.dart

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class TripPlannerScreen extends StatefulWidget {
  const TripPlannerScreen({Key? key}) : super(key: key);

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final DateFormat _dateFormat = DateFormat('d.M.yyyy');

  bool _isGeneratingPacking = false;
  List<Map<String, dynamic>> _wardrobe = [];

  @override
  void initState() {
    super.initState();
    _loadWardrobeFromFirestore();
  }

  Future<void> _loadWardrobeFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .get();

      setState(() {
        _wardrobe = snapshot.docs
            .map((d) => d.data())
            .whereType<Map<String, dynamic>>()
            .toList();
      });
    } catch (e) {
      debugPrint('Chyba pri načítavaní šatníka pre trip planner: $e');
    }
  }

  String _formatDate(DateTime date) => _dateFormat.format(date);

  DateTime _parseDateOrToday(String? iso) {
    if (iso == null) return DateTime.now();
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dovolenka / pracovná cesta'),
        ),
        body: const Center(
          child: Text('Nie si prihlásený.'),
        ),
      );
    }

    final tripsRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('trips');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dovolenka / pracovná cesta'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTripForm(context: context),
        icon: const Icon(Icons.add),
        label: const Text('Pridať cestu'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: tripsRef.orderBy('startDate').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Chyba pri načítavaní ciest.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'Zatiaľ nemáš pridanú žiadnu dovolenku ani pracovnú cestu.\n\n'
                      'Pridaj si prvú a ja ti pomôžem vymyslieť, čo si zbaliť podľa destinácie a počasia. 🌍🎒',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final destination =
                  (data['destinationName'] as String?) ?? 'Neznáma destinácia';
              final type = (data['tripType'] as String?) ?? 'dovolenka';
              final startIso = data['startDate'] as String?;
              final endIso = data['endDate'] as String?;
              final travelMode = data['travelMode'] as String? ?? 'auto';
              final packingSuggestion = data['packingSuggestion'] as String?;

              final start = _parseDateOrToday(startIso);
              final end = _parseDateOrToday(endIso);

              final emoji = switch (type) {
                'pracovná cesta' => '💼',
                _ => '🏖️',
              };

              final travelEmoji = switch (travelMode) {
                'auto' => '🚗',
                'lietadlo' => '✈️',
                'vlak' => '🚆',
                'autobus' => '🚌',
                _ => '🧳',
              };

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    _showTripDetail(
                      context: context,
                      docId: doc.id,
                      data: data,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                destination,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${type[0].toUpperCase()}${type.substring(1)} • ${_formatDate(start)} – ${_formatDate(end)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$travelEmoji  $travelMode',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (packingSuggestion != null &&
                                  packingSuggestion.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Máš uložený zoznam, čo si zbaliť.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.green[700]),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openTripForm({
    required BuildContext context,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final _formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final destinationController = TextEditingController();
    final notesController = TextEditingController();

    String tripType = 'dovolenka';
    String travelMode = 'lietadlo';

    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 7));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;

        return Padding(
          padding: EdgeInsets.only(
            bottom: viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> pickDate({
                required bool isStart,
              }) async {
                final initial = isStart ? startDate : endDate;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime.now()
                      .subtract(const Duration(days: 1)),
                  lastDate: DateTime.now()
                      .add(const Duration(days: 365 * 2)),
                );
                if (picked != null) {
                  setModalState(() {
                    if (isStart) {
                      startDate = picked;
                      if (endDate.isBefore(startDate)) {
                        endDate = startDate;
                      }
                    } else {
                      endDate = picked.isBefore(startDate)
                          ? startDate
                          : picked;
                    }
                  });
                }
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Text(
                          'Nová cesta',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Názov (napr. Malorka s Kristínou)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Napíš aspoň krátky názov.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: tripType,
                          decoration: const InputDecoration(
                            labelText: 'Typ cesty',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'dovolenka',
                              child: Text('Dovolenka'),
                            ),
                            DropdownMenuItem(
                              value: 'pracovná cesta',
                              child: Text('Pracovná cesta'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setModalState(() {
                              tripType = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: destinationController,
                          decoration: const InputDecoration(
                            labelText: 'Destinácia (mesto, krajina)',
                            hintText: 'Napr. Barcelona, Španielsko',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Napíš aspoň mesto alebo krajinu.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(isStart: true),
                                icon: const Icon(Icons.calendar_today),
                                label: Text(
                                  'Od: ${_formatDate(startDate)}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => pickDate(isStart: false),
                                icon: const Icon(Icons.calendar_today),
                                label: Text(
                                  'Do: ${_formatDate(endDate)}',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: travelMode,
                          decoration: const InputDecoration(
                            labelText: 'Spôsob cestovania',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'lietadlo',
                              child: Text('Lietadlo'),
                            ),
                            DropdownMenuItem(
                              value: 'auto',
                              child: Text('Auto'),
                            ),
                            DropdownMenuItem(
                              value: 'vlak',
                              child: Text('Vlak'),
                            ),
                            DropdownMenuItem(
                              value: 'autobus',
                              child: Text('Autobus'),
                            ),
                            DropdownMenuItem(
                              value: 'iné',
                              child: Text('Iné'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setModalState(() {
                              travelMode = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Poznámky (voliteľné)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (!_formKey.currentState!.validate()) return;

                              final user = _auth.currentUser;
                              if (user == null) return;

                              final tripsRef = _firestore
                                  .collection('users')
                                  .doc(user.uid)
                                  .collection('trips');

                              await tripsRef.add({
                                'title': titleController.text.trim(),
                                'tripType': tripType,
                                'destinationName':
                                destinationController.text.trim(),
                                'travelMode': travelMode,
                                'startDate': DateFormat('yyyy-MM-dd')
                                    .format(startDate),
                                'endDate': DateFormat('yyyy-MM-dd')
                                    .format(endDate),
                                'notes': notesController.text.trim(),
                                'packingSuggestion': '',
                                'createdAt': FieldValue.serverTimestamp(),
                              });

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('Uložiť cestu'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showTripDetail({
    required BuildContext context,
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final destination =
        (data['destinationName'] as String?) ?? 'Neznáma destinácia';
    final type = (data['tripType'] as String?) ?? 'dovolenka';
    final travelMode = data['travelMode'] as String? ?? 'auto';
    final startIso = data['startDate'] as String?;
    final endIso = data['endDate'] as String?;
    final notes = data['notes'] as String? ?? '';
    final packingSuggestion = data['packingSuggestion'] as String? ?? '';

    final start = _parseDateOrToday(startIso);
    final end = _parseDateOrToday(endIso);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;

        return Padding(
          padding: EdgeInsets.only(
            bottom: viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> generatePacking() async {
                setModalState(() {
                  _isGeneratingPacking = true;
                });

                try {
                  final suggestion = await _callPackingApi(
                    tripData: data,
                    wardrobe: _wardrobe,
                  );

                  final user = _auth.currentUser;
                  if (user != null) {
                    final tripRef = _firestore
                        .collection('users')
                        .doc(user.uid)
                        .collection('trips')
                        .doc(docId);

                    await tripRef.update({
                      'packingSuggestion': suggestion,
                    });
                  }

                  if (context.mounted) {
                    setModalState(() {
                      data['packingSuggestion'] = suggestion;
                    });
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Nepodarilo sa vygenerovať zoznam. Skús znova. ($e)',
                        ),
                      ),
                    );
                  }
                } finally {
                  setModalState(() {
                    _isGeneratingPacking = false;
                  });
                }
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Text(
                        destination,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${type[0].toUpperCase()}${type.substring(1)} • ${_formatDate(start)} – ${_formatDate(end)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Spôsob cestovania: $travelMode',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Poznámky:',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notes,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (packingSuggestion.isNotEmpty) ...[
                        Text(
                          'Uložený zoznam, čo si zbaliť:',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            data['packingSuggestion'] as String,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                          _isGeneratingPacking ? null : generatePacking,
                          icon: _isGeneratingPacking
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                              : const Icon(Icons.checklist_outlined),
                          label: Text(
                            _isGeneratingPacking
                                ? 'Generujem zoznam...'
                                : 'Navrhni, čo si mám zbaliť',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<String> _callPackingApi({
    required Map<String, dynamic> tripData,
    required List<Map<String, dynamic>> wardrobe,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    // Upravíme šatník do formátu, ktorý vie jsonEncode spracovať
    final wardrobeForApi = wardrobe.map((item) {
      return item.map((key, value) {
        if (value is Timestamp) {
          return MapEntry(
            key,
            value.toDate().toIso8601String(),
          );
        }
        return MapEntry(key, value);
      });
    }).toList();

    // TODO: nahraď túto URL reálnou HTTPS Cloud Function adresou
    const String functionUrl =
        'https://us-central1-outfitoftheday-4d401.cloudfunctions.net/planTripPackingList';


    final body = {
      'userId': user.uid,
      'trip': tripData,
      'wardrobe': wardrobeForApi,
    };

    final response = await http.post(
      Uri.parse(functionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      debugPrint(
          'Packing API error: ${response.statusCode} - ${response.body}');
      throw Exception('Packing API returned status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestion = data['packingSuggestion'] as String?;

    if (suggestion == null || suggestion.trim().isEmpty) {
      return 'Prepáč, teraz sa mi nepodarilo vymyslieť konkrétny zoznam. Skús to prosím ešte raz neskôr. 💫';
    }

    return suggestion;
  }
}
