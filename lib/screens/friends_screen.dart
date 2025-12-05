import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'messages_screen.dart';

/// Základná obrazovka so zoznamom priateľov.
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Priatelia'),
        ),
        body: const Center(
          child: Text('Musíš byť prihlásený, aby si videl priateľov.'),
        ),
      );
    }

    final friendshipsCollection =
    FirebaseFirestore.instance.collection('friendships');

    final friendsStream = friendshipsCollection
        .where('participants', arrayContains: user.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Priatelia'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: friendsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Chyba pri načítaní priateľov: ${snapshot.error}'),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const _EmptyFriendsView();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12.0),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};

              final List<dynamic> participants =
              (data['participants'] as List<dynamic>? ?? []);
              if (!participants.contains(user.uid) || participants.length != 2) {
                return const SizedBox.shrink();
              }

              final String uidA = data['userA'] as String? ?? '';
              final String uidB = data['userB'] as String? ?? '';
              final String displayNameA = data['displayNameA'] as String? ?? '';
              final String displayNameB = data['displayNameB'] as String? ?? '';
              final String relationshipType =
                  data['relationshipType'] as String? ?? 'neuvedené';

              final bool iAmA = uidA == user.uid;
              final String friendUid = iAmA ? uidB : uidA;
              final String friendName =
              iAmA ? (displayNameB.isNotEmpty ? displayNameB : friendUid) : (displayNameA.isNotEmpty ? displayNameA : friendUid);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(friendName),
                  subtitle: Text('Vzťah: $relationshipType'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FriendDetailScreen(
                          friendshipId: doc.id,
                          friendUid: friendUid,
                          friendName: friendName,
                          relationshipType: relationshipType,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showAddFriendBottomSheet(context);
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Pridať priateľa'),
      ),
    );
  }
}

class _EmptyFriendsView extends StatelessWidget {
  const _EmptyFriendsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.group_outlined, size: 64),
            SizedBox(height: 16),
            Text(
              'Zatiaľ nemáš pridaných žiadnych priateľov.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Klikni na tlačidlo „Pridať priateľa“ a pozvi partnerku, kamošov alebo rodinu.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail priateľa – meno/prezývka + typ vzťahu + tlačidlo na zladenie outfitu.
class FriendDetailScreen extends StatelessWidget {
  final String friendshipId;
  final String friendUid;
  final String friendName;
  final String relationshipType;

  const FriendDetailScreen({
    super.key,
    required this.friendshipId,
    required this.friendUid,
    required this.friendName,
    required this.relationshipType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(friendName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person),
              ),
              title: Text(friendName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Text('Vzťah: $relationshipType'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Zladenie outfitov',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pošli žiadosť o zladenie outfitov na konkrétnu udalosť. '
                  'AI ti neskôr pomôže nájsť outfit pre teba aj pre priateľa, aby ste spolu ladili.',
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateMatchRequestScreen(
                        friendUid: friendUid,
                        friendName: friendName,
                        relationshipType: relationshipType,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.favorite_border),
                label: const Text('Požiadať o zladenie outfitu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet na pridanie priateľa podľa e-mailu + typu vzťahu.
Future<void> _showAddFriendBottomSheet(BuildContext context) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  final emailController = TextEditingController();
  String? relationshipType;
  bool isSaving = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final bottom = MediaQuery.of(context).viewInsets.bottom;

          Future<void> saveFriend() async {
            final email = emailController.text.trim();
            if (email.isEmpty || relationshipType == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Zadaj e-mail priateľa a typ vzťahu.'),
                ),
              );
              return;
            }

            if (email == currentUser.email) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nemôžeš pridať sám seba ako priateľa.'),
                ),
              );
              return;
            }

            setState(() {
              isSaving = true;
            });

            try {
              // Nájdeme užívateľa podľa e-mailu v kolekcii "users".
              final userQuery = await FirebaseFirestore.instance
                  .collection('users')
                  .where('email', isEqualTo: email)
                  .limit(1)
                  .get();

              if (userQuery.docs.isEmpty) {
                setState(() {
                  isSaving = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                    Text('Používateľ s týmto e-mailom neexistuje v aplikácii.'),
                  ),
                );
                return;
              }

              final friendDoc = userQuery.docs.first;
              final friendUid = friendDoc.id;
              final friendData =
                  friendDoc.data() as Map<String, dynamic>? ?? {};
              final friendDisplayName =
                  friendData['displayName'] as String? ?? email;

              final myDisplayName =
                  currentUser.displayName ?? currentUser.email ?? 'Ja';

              // Vytvoríme friendship dokument v kolekcii "friendships".
              final friendshipsCollection =
              FirebaseFirestore.instance.collection('friendships');

              await friendshipsCollection.add({
                'participants': [currentUser.uid, friendUid],
                'userA': currentUser.uid,
                'userB': friendUid,
                'displayNameA': myDisplayName,
                'displayNameB': friendDisplayName,
                'relationshipType': relationshipType,
                'status': 'accepted', // jednoduchá prvá verzia
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });

              Navigator.of(context).pop();
            } catch (e) {
              setState(() {
                isSaving = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Chyba pri pridávaní priateľa: $e'),
                ),
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Pridať priateľa',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail priateľa',
                      hintText: 'napr. partner@domena.sk',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: relationshipType,
                    decoration: const InputDecoration(
                      labelText: 'Typ vzťahu',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'partner',
                        child: Text('Partner / partnerka'),
                      ),
                      DropdownMenuItem(
                        value: 'kamarat',
                        child: Text('Kamarát / kamarátka'),
                      ),
                      DropdownMenuItem(
                        value: 'rodina',
                        child: Text('Rodina'),
                      ),
                      DropdownMenuItem(
                        value: 'kolega',
                        child: Text('Kolega / kolegyňa'),
                      ),
                      DropdownMenuItem(
                        value: 'ine',
                        child: Text('Iné'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        relationshipType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : saveFriend,
                      child: isSaving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : const Text('Uložiť priateľa'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
