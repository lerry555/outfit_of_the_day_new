import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Services/wardrobe_set_repository.dart';
import '../domain/wardrobe_v2/wardrobe_set_v2.dart';
import '../utils/wardrobe_image_url_priority.dart';

typedef CaptureSetComponent =
    Future<String?> Function(
      BuildContext hostContext,
      VoidCallback onAnalyzerRequest,
    );

class WardrobeSetCreationScreen extends StatefulWidget {
  const WardrobeSetCreationScreen({
    super.key,
    required this.captureNewItem,
    this.initialMemberIds = const [],
    this.existingDraftId,
  });
  final CaptureSetComponent captureNewItem;
  final List<String> initialMemberIds;
  final String? existingDraftId;

  @override
  State<WardrobeSetCreationScreen> createState() =>
      _WardrobeSetCreationScreenState();
}

class _WardrobeSetCreationScreenState extends State<WardrobeSetCreationScreen> {
  final _repository = WardrobeSetRepository();
  late final _selected = widget.initialMemberIds.toSet();
  late final String _draftId =
      widget.existingDraftId ??
      'set-draft-${DateTime.now().microsecondsSinceEpoch}';
  var _type = WardrobeSetTypeV2.matchingSet;
  var _source = WardrobeSetRelationshipSourceV2.manufacturerMatching;
  final Map<String, Map<String, dynamic>> _componentCheckpoints = {};
  int _inferenceCount = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final id in widget.initialMemberIds) {
      _componentCheckpoints['existing-$id'] = {
        'componentId': 'existing-$id',
        'status': 'saved',
        'source': 'existing_wardrobe',
        'itemId': id,
      };
    }
    if (widget.existingDraftId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateDraft());
    }
  }

  Future<void> _hydrateDraft() async {
    final draft = await _repository.getDraft(_draftId);
    if (!mounted || draft == null) return;
    final members = (draft['memberIds'] as List?)
        ?.map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (members == null || members.isEmpty) return;
    setState(() {
      _selected.addAll(members);
      for (final id in members) {
        _componentCheckpoints['existing-$id'] ??= {
          'componentId': 'existing-$id',
          'status': 'saved',
          'source': 'existing_wardrobe',
          'itemId': id,
        };
      }
    });
  }

  Future<void> _checkpoint({String? failedStage}) =>
      _repository.saveDraft(_draftId, {
        'schemaVersion': '1.0.0',
        'status': _selected.length >= 2 ? 'ready_to_complete' : 'incomplete',
        'memberIds': _selected.toList(),
        'components': _componentCheckpoints.values.toList(growable: false),
        'setType': _type.wireName,
        'relationshipSource': _source.wireName,
        'authority': 'user_confirmation',
        'inferenceCount': _inferenceCount,
        if (failedStage != null) 'lastFailureStage': failedStage,
      });

  Future<void> _capture() async {
    if (_selected.length >= WardrobeSetRepository.maxUiMembers) return;
    final componentId = 'component-${DateTime.now().microsecondsSinceEpoch}';
    _componentCheckpoints[componentId] = {
      'componentId': componentId,
      'status': 'not_started',
      'source': 'new_photo',
    };
    await _checkpoint();
    final id = await widget.captureNewItem(context, () {
      _inferenceCount += 1;
      _componentCheckpoints[componentId] = {
        ..._componentCheckpoints[componentId]!,
        'status': 'analyzing',
        'inferenceAttempts':
            ((_componentCheckpoints[componentId]!['inferenceAttempts'] as num?)
                    ?.toInt() ??
                0) +
            1,
      };
      _checkpoint();
    });
    if (!mounted) return;
    if (id == null) {
      _componentCheckpoints[componentId] = {
        ..._componentCheckpoints[componentId]!,
        'status': 'failed',
        'failureStage': 'component_flow',
      };
      await _checkpoint(
        failedStage: _selected.isEmpty ? 'first_component' : 'later_component',
      );
      setState(
        () => _error = _selected.isEmpty
            ? 'Prvý kúsok sa nepodarilo pridať. Skús znova alebo pridaj iný kúsok.'
            : 'Set zatiaľ nie je dokončený. Uložené kúsky zostávajú v Šatníku a môžeš pokračovať neskôr.',
      );
      return;
    }
    setState(() {
      _selected.add(id);
      _error = null;
    });
    _componentCheckpoints[componentId] = {
      ..._componentCheckpoints[componentId]!,
      'status': 'saved',
      'itemId': id,
    };
    await _repository.markPendingMember(_draftId, id);
    await _checkpoint();
  }

  Future<void> _complete() async {
    if (_selected.length < 2 || _busy) return;
    setState(() => _busy = true);
    try {
      await _repository.createSet(
        memberIds: _selected,
        setType: _type,
        relationshipSource: _source,
      );
      await _repository.abandonDraft(_draftId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      await _checkpoint(failedStage: 'set_commit');
      if (mounted)
        setState(() => _error = 'Set sa nepodarilo dokončiť: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Pridať set / súpravu')),
      body: uid == null
          ? const Center(child: Text('Musíš byť prihlásený.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('wardrobe')
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final header = <Widget>[
                  const Text(
                    'Každý fyzický kúsok odfoť samostatne. Uložené kúsky môžeš nosiť aj bez zvyšku setu.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'Typ setu'),
                    items: WardrobeSetTypeV2.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.labelSk),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField(
                    value: _source,
                    decoration: const InputDecoration(
                      labelText: 'Ako tento set vznikol?',
                    ),
                    items: WardrobeSetRelationshipSourceV2.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.labelSk),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _source = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Kúsky ${_selected.length}/${WardrobeSetRepository.maxUiMembers}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed:
                        _selected.length >= WardrobeSetRepository.maxUiMembers
                        ? null
                        : _capture,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Odfotiť nový kúsok'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('alebo vyber existujúce kúsky zo Šatníka'),
                  ),
                ];
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: header.length + docs.length,
                        itemBuilder: (context, index) {
                          if (index < header.length) return header[index];
                          return _existingItemTile(docs[index - header.length]);
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            Semantics(
                              identifier: 'ootd_create_set',
                              button: true,
                              child: FilledButton(
                                onPressed: _selected.length >= 2 && !_busy
                                    ? _complete
                                    : null,
                                child: Text(
                                  _busy ? 'Ukladám…' : 'Vytvoriť set',
                                ),
                              ),
                            ),
                            if (_selected.length == 1)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Na dokončenie setu pridaj ešte aspoň jeden kúsok. Prvý kúsok zostáva normálne v Šatníku.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _existingItemTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final membership = data['setMembership'];
    final alreadyLinked =
        membership is Map && (membership['setId'] ?? '').toString().isNotEmpty;
    return CheckboxListTile(
      value: _selected.contains(doc.id),
      enabled:
          !alreadyLinked &&
          (_selected.contains(doc.id) ||
              _selected.length < WardrobeSetRepository.maxUiMembers),
      title: Text((data['name'] ?? 'Kúsok').toString()),
      subtitle: alreadyLinked ? const Text('Už patrí do iného setu') : null,
      secondary: _thumb(data),
      onChanged: (checked) async {
        setState(() {
          checked == true ? _selected.add(doc.id) : _selected.remove(doc.id);
        });
        if (checked == true) {
          _componentCheckpoints['existing-${doc.id}'] = {
            'componentId': 'existing-${doc.id}',
            'status': 'saved',
            'source': 'existing_wardrobe',
            'itemId': doc.id,
          };
          await _repository.markPendingMember(_draftId, doc.id);
        } else {
          _componentCheckpoints.remove('existing-${doc.id}');
          await _repository.clearPendingMember(doc.id);
        }
        await _checkpoint();
      },
    );
  }

  Widget _thumb(Map<String, dynamic> data) {
    final url = getBestWardrobeImageUrlOrNull(data);
    return SizedBox(
      width: 48,
      height: 48,
      child: url == null
          ? const Icon(Icons.checkroom)
          : Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 96,
              errorBuilder: (_, __, ___) => const Icon(Icons.checkroom),
            ),
    );
  }
}

class WardrobeSetDetailScreen extends StatefulWidget {
  const WardrobeSetDetailScreen({
    super.key,
    required this.setId,
    this.captureNewItem,
  });
  final String setId;
  final CaptureSetComponent? captureNewItem;
  @override
  State<WardrobeSetDetailScreen> createState() =>
      _WardrobeSetDetailScreenState();
}

class _WardrobeSetDetailScreenState extends State<WardrobeSetDetailScreen> {
  final _repository = WardrobeSetRepository();

  Future<void> _rename(WardrobeSetV2 set) async {
    final controller = TextEditingController(text: set.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Premenovať set'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Uložiť'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await _repository.updateSet(set.setId, userLabel: value);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editSemantics(WardrobeSetV2 set) async {
    var type = set.setType;
    var source = set.relationshipSource;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Upraviť set'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField(
                value: type,
                items: WardrobeSetTypeV2.values
                    .map(
                      (x) => DropdownMenuItem(value: x, child: Text(x.labelSk)),
                    )
                    .toList(),
                onChanged: (x) => update(() => type = x ?? type),
                decoration: const InputDecoration(labelText: 'Typ setu'),
              ),
              DropdownButtonFormField(
                value: source,
                items: WardrobeSetRelationshipSourceV2.values
                    .map(
                      (x) => DropdownMenuItem(value: x, child: Text(x.labelSk)),
                    )
                    .toList(),
                onChanged: (x) => update(() => source = x ?? source),
                decoration: const InputDecoration(labelText: 'Vzťah kúskov'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Späť'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Uložiť'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await _repository.updateSet(
        set.setId,
        setType: type,
        relationshipSource: source,
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _addNew(WardrobeSetV2 set) async {
    final capture = widget.captureNewItem;
    if (capture == null) return;
    final itemId = await capture(context, () {});
    if (itemId != null) {
      await _repository.addMember(set.setId, itemId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _addExisting(WardrobeSetV2 set) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wardrobe')
        .get();
    if (!mounted) return;
    final candidates = snapshot.docs.where((doc) {
      if (set.memberIds.contains(doc.id)) return false;
      final membership = doc.data()['setMembership'];
      return membership is! Map ||
          (membership['setId'] ?? '').toString().isEmpty;
    }).toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Vybrať kúsok zo šatníka'),
        children: candidates
            .map(
              (doc) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, doc.id),
                child: Text((doc.data()['name'] ?? 'Kúsok').toString()),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      await _repository.addMember(set.setId, selected);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _chooseExisting(WardrobeSetV2 set) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wardrobe')
        .get();
    if (!mounted) return null;
    final candidates = snapshot.docs.where((doc) {
      if (set.memberIds.contains(doc.id)) return false;
      final membership = doc.data()['setMembership'];
      return membership is! Map ||
          (membership['setId'] ?? '').toString().isEmpty;
    });
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Vybrať náhradu zo šatníka'),
        children: candidates
            .map(
              (doc) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, doc.id),
                child: Text((doc.data()['name'] ?? 'Kúsok').toString()),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _manageMember(WardrobeSetV2 set, String memberId) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.captureNewItem != null)
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: const Text('Nahradiť novým kúskom'),
                onTap: () => Navigator.pop(context, 'new'),
              ),
            ListTile(
              leading: const Icon(Icons.checkroom),
              title: const Text('Vybrať náhradu zo šatníka'),
              onTap: () => Navigator.pop(context, 'existing'),
            ),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Odstrániť bez náhrady'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'remove') {
      await _repository.removeMember(set.setId, memberId);
    } else {
      final replacement = action == 'new'
          ? await widget.captureNewItem?.call(context, () {})
          : await _chooseExisting(set);
      if (replacement == null) return;
      await _repository.replaceMember(
        set.setId,
        removedItemId: memberId,
        replacementItemId: replacement,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _dissolve() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zrušiť set?'),
        content: const Text(
          'Odstráni sa iba vzťah medzi kúskami. Oblečenie zostane v Šatníku.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Späť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zrušiť set'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _repository.dissolveSet(widget.setId);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WardrobeSetV2?>(
    future: _repository.getSet(widget.setId),
    builder: (context, snapshot) {
      final set = snapshot.data;
      return Scaffold(
        appBar: AppBar(title: Text(set?.displayName ?? 'Set')),
        body: set == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    leading: Icon(
                      WardrobeSetPresentationV2.icon(set.setId),
                      color: WardrobeSetPresentationV2.borderColor(set.setId),
                    ),
                    title: Text(set.setType.labelSk),
                    subtitle: Text(set.relationshipSource.labelSk),
                  ),
                  const Divider(),
                  ...set.memberIds.map(
                    (id) =>
                        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .collection('wardrobe')
                              .doc(id)
                              .get(),
                          builder: (context, itemSnapshot) {
                            final data = itemSnapshot.data?.data();
                            return ListTile(
                              title: Text(
                                (data?['name'] ?? 'Kúsok').toString(),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_horiz),
                                tooltip: 'Spravovať kúsok',
                                onPressed: () => _manageMember(set, id),
                              ),
                            );
                          },
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            set.memberIds.length >=
                                WardrobeSetRepository.maxUiMembers
                            ? null
                            : () => _addExisting(set),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Pridať zo šatníka'),
                      ),
                      if (widget.captureNewItem != null)
                        OutlinedButton.icon(
                          onPressed:
                              set.memberIds.length >=
                                  WardrobeSetRepository.maxUiMembers
                              ? null
                              : () => _addNew(set),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Pridať nový kúsok'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _rename(set),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Premenovať'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _editSemantics(set),
                        icon: const Icon(Icons.tune),
                        label: const Text('Upraviť typ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    identifier: 'ootd_dissolve_set',
                    button: true,
                    child: OutlinedButton.icon(
                      onPressed: _dissolve,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Zrušiť set'),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}
