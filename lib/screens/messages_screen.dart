import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Hlavný screen: Správy a zladenie outfitov.
/// Tab 1: Zladenie outfitov (s otvorené/uzavreté)
/// Tab 2: Chaty (placeholder na budúce bežné správy)
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Správy a zladenie outfitov'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.diversity_2),
                text: 'Zladenie outfitov',
              ),
              Tab(
                icon: Icon(Icons.chat_bubble_outline),
                text: 'Chaty',
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MatchRequestsTab(),
            _ChatsTabPlaceholder(),
          ],
        ),
      ),
    );
  }
}

/// Tab pre zladenie outfitov – má prepínač Otvorené / Uzavreté
class _MatchRequestsTab extends StatefulWidget {
  const _MatchRequestsTab();

  @override
  State<_MatchRequestsTab> createState() => _MatchRequestsTabState();
}

class _MatchRequestsTabState extends State<_MatchRequestsTab> {
  bool showOpen = true; // true = otvorené, false = uzavreté

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Otvorené'),
                  selected: showOpen,
                  onSelected: (val) {
                    setState(() {
                      showOpen = true;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Uzavreté'),
                  selected: !showOpen,
                  onSelected: (val) {
                    setState(() {
                      showOpen = false;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _MatchRequestsList(status: showOpen ? 'open' : 'closed'),
        ),
      ],
    );
  }
}

/// Zoznam žiadostí o zladenie outfitov (podľa statusu: open/closed)
class _MatchRequestsList extends StatelessWidget {
  final String status;

  const _MatchRequestsList({required this.status});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text('Musíš byť prihlásený, aby si videl zladenia.'),
      );
    }

    final matchRequestsCollection =
    FirebaseFirestore.instance.collection('matchRequests');

    final stream = matchRequestsCollection
        .where('participants', arrayContains: user.uid)
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Chyba pri načítaní žiadostí: ${snapshot.error}'),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                status == 'open'
                    ? 'Nemáš žiadne otvorené žiadosti o zladenie.'
                    : 'Nemáš žiadne uzavreté žiadosti o zladenie.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>? ?? {};

            final fromUid = data['fromUid'] as String? ?? '';
            final toUid = data['toUid'] as String? ?? '';
            final fromName = data['fromName'] as String? ?? 'Niekto';
            final toName = data['toName'] as String? ?? 'Niekto';
            final eventType = data['eventType'] as String? ?? 'Udalosť';
            final relationshipType =
                data['relationshipType'] as String? ?? 'vzťah';
            final createdAtTs = data['createdAt'] as Timestamp?;
            final createdAt = createdAtTs?.toDate();

            final isIncoming = toUid == user.uid;
            final otherName = isIncoming ? fromName : toName;

            final subtitle = StringBuffer();
            subtitle.write(
                isIncoming ? 'Od: $fromName' : 'Pre: $toName');
            subtitle.write(' · $eventType');
            subtitle.write(' · vzťah: $relationshipType');

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              child: ListTile(
                leading: Icon(
                  isIncoming ? Icons.inbox : Icons.outbox,
                  color: isIncoming ? Colors.blue : Colors.green,
                ),
                title: Text('S $otherName'),
                subtitle: Text(subtitle.toString()),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      status == 'open' ? 'Otvorená' : 'Uzavretá',
                      style: TextStyle(
                        color: status == 'open'
                            ? Colors.orange
                            : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        _formatDate(createdAt),
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MatchRequestDetailScreen(
                        requestId: doc.id,
                        data: data,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// Detail konkrétnej žiadosti o zladenie outfitu.
class MatchRequestDetailScreen extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;

  const MatchRequestDetailScreen({
    super.key,
    required this.requestId,
    required this.data,
  });

  @override
  State<MatchRequestDetailScreen> createState() =>
      _MatchRequestDetailScreenState();
}

class _MatchRequestDetailScreenState extends State<MatchRequestDetailScreen> {
  bool _isClosing = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final fromName = data['fromName'] as String? ?? 'Niekto';
    final toName = data['toName'] as String? ?? 'Niekto';
    final relationshipType =
        data['relationshipType'] as String? ?? 'vzťah';
    final eventType = data['eventType'] as String? ?? 'Udalosť';
    final contextText =
        data['context'] as String? ?? ''; // popis udalosti / miesto
    final userMessage =
        data['userMessage'] as String? ?? ''; // text pri vytvorení
    final status = data['status'] as String? ?? 'open';

    final createdAtTs = data['createdAt'] as Timestamp?;
    final createdAt = createdAtTs?.toDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail zladenia'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text('$fromName  ⇄  $toName'),
            subtitle: Text('Vzťah: $relationshipType'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text('Udalosť: $eventType'),
            subtitle: Text(
              contextText.isNotEmpty ? contextText : 'Bez bližšieho popisu',
            ),
          ),
          if (createdAt != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Vytvorené'),
              subtitle: Text(_formatDateTime(createdAt)),
            ),
          ],
          if (userMessage.isNotEmpty) ...[
            const Divider(),
            const Text(
              'Správa pri vytvorení žiadosti',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(userMessage),
          ],
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Stav žiadosti'),
            subtitle: Text(
              status == 'open'
                  ? 'Otvorená – môžete sa ešte dohadovať.'
                  : 'Uzavretá.',
            ),
          ),
          const SizedBox(height: 16),
          if (status == 'open')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isClosing ? null : _closeRequest,
                icon: _isClosing
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isClosing ? 'Označujem...' : 'Označiť žiadosť ako uzavretú',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _closeRequest() async {
    setState(() {
      _isClosing = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('matchRequests')
          .doc(widget.requestId)
          .update({
        'status': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Žiadosť bola označená ako uzavretá.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isClosing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri uzatváraní žiadosti: $e')),
      );
    }
  }
}

/// Obrazovka na vytvorenie žiadosti o zladenie outfitu.
/// Toto voláme z FriendDetailScreen.
class CreateMatchRequestScreen extends StatefulWidget {
  final String friendUid;
  final String friendName;
  final String relationshipType;

  const CreateMatchRequestScreen({
    super.key,
    required this.friendUid,
    required this.friendName,
    required this.relationshipType,
  });

  @override
  State<CreateMatchRequestScreen> createState() =>
      _CreateMatchRequestScreenState();
}

class _CreateMatchRequestScreenState extends State<CreateMatchRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _eventType;
  DateTime? _eventDate;
  final TextEditingController _contextController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _contextController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Zladenie outfitu'),
        ),
        body: const Center(
          child: Text('Musíš byť prihlásený.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Zladenie s ${widget.friendName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'Žiadosť o zladenie outfitov',
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Vytvorí sa žiadosť medzi tebou a ${widget.friendName}. '
                    'Neskôr ju AI využije na návrh párových outfitov.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _eventType,
                decoration: const InputDecoration(
                  labelText: 'Typ udalosti',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'rande',
                    child: Text('Rande'),
                  ),
                  DropdownMenuItem(
                    value: 'svadba',
                    child: Text('Svadba'),
                  ),
                  DropdownMenuItem(
                    value: 'pracovne',
                    child: Text('Pracovné stretnutie'),
                  ),
                  DropdownMenuItem(
                    value: 'party',
                    child: Text('Párty'),
                  ),
                  DropdownMenuItem(
                    value: 'bezne',
                    child: Text('Bežný deň'),
                  ),
                  DropdownMenuItem(
                    value: 'ine',
                    child: Text('Iné'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _eventType = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vyber typ udalosti.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _pickEventDate(context),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Dátum udalosti (nepovinné)',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _eventDate != null
                        ? _formatDateTime(_eventDate!)
                        : 'Vyber dátum (ak vieš)',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contextController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Popis / miesto udalosti (nepovinné)',
                  hintText: 'Napr. reštaurácia, fotenie, rodinná oslava...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Správa pre priateľa',
                  hintText:
                  'Vlastnými slovami: čo by si chcel zladiť, aké farby máš rád, atď.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _saveRequest(context, currentUser),
                  icon: _isSaving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Icon(Icons.send),
                  label: Text(
                    _isSaving ? 'Odosielam...' : 'Odoslať žiadosť',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickEventDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _eventDate = picked;
      });
    }
  }

  Future<void> _saveRequest(
      BuildContext context, User currentUser) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final matchRequestsCollection =
      FirebaseFirestore.instance.collection('matchRequests');

      final fromName =
          currentUser.displayName ?? currentUser.email ?? 'Ja';
      final toName = widget.friendName;

      final docRef = await matchRequestsCollection.add({
        'participants': [currentUser.uid, widget.friendUid],
        'fromUid': currentUser.uid,
        'toUid': widget.friendUid,
        'fromName': fromName,
        'toName': toName,
        'relationshipType': widget.relationshipType,
        'eventType': _eventType ?? 'bezne',
        'eventDate': _eventDate != null
            ? Timestamp.fromDate(_eventDate!)
            : null,
        'context': _contextController.text.trim(),
        'userMessage': _messageController.text.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Žiadosť o zladenie bola odoslaná.'),
          ),
        );
        Navigator.of(context).pop(); // zatvoriť CreateMatchRequestScreen
        // Voliteľne otvoríme detail žiadosti
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchRequestDetailScreen(
              requestId: docRef.id,
              data: {
                'fromName': fromName,
                'toName': toName,
                'relationshipType': widget.relationshipType,
                'eventType': _eventType ?? 'bezne',
                'eventDate': _eventDate != null
                    ? Timestamp.fromDate(_eventDate!)
                    : null,
                'context': _contextController.text.trim(),
                'userMessage': _messageController.text.trim(),
                'status': 'open',
                'createdAt': Timestamp.now(),
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba pri vytváraní žiadosti: $e'),
        ),
      );
    }
  }
}

/// Placeholder pre bežné chaty – doplníme neskôr.
class _ChatsTabPlaceholder extends StatelessWidget {
  const _ChatsTabPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text(
          'Bežné chaty medzi priateľmi sem pridáme čoskoro.\n'
              'Zatiaľ môžeš používať zladenie outfitov.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year}';
}

String _formatDateTime(DateTime dateTime) {
  final d = _formatDate(dateTime);
  final h = dateTime.hour.toString().padLeft(2, '0');
  final m = dateTime.minute.toString().padLeft(2, '0');
  return '$d $h:$m';
}
