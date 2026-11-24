import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/wardrobe_image_url_priority.dart';
import '../utils/wardrobe_list_utils.dart';

/// Real user wardrobe, strictly display-only. Never invokes writes, uploads,
/// AI calls, or production mutation services.
class WardrobeReadOnlyCoverFlow extends StatefulWidget {
  const WardrobeReadOnlyCoverFlow({super.key});

  @override
  State<WardrobeReadOnlyCoverFlow> createState() => _WardrobeReadOnlyCoverFlowState();
}

class _WardrobeReadOnlyCoverFlowState extends State<WardrobeReadOnlyCoverFlow> {
  static const gold = Color(0xFFC8A36A);
  String category = 'Topy';
  String filter = 'Všetko';
  int current = 0;

  static const groups = <String, List<String>>{
    'Topy': ['Tričká', 'Polokošele', 'Tielka', 'Košele', 'Mikiny', 'Svetre'],
    'Nohavice': ['Rifle', 'Nohavice', 'Kraťasy'],
    'Bundy': ['Bundy', 'Kabáty', 'Vesty'],
    'Obuv': ['Tenisky', 'Topánky', 'Čižmy', 'Sandále'],
    'Doplnky': ['Čiapky', 'Opasky', 'Tašky'],
  };

  String _haystack(Map<String, dynamic> data) =>
      ['name', 'category', 'categoryKey', 'categoryLabel', 'subCategory',
       'subCategoryKey', 'subCategoryLabel', 'mainGroup', 'mainGroupKey']
      .map((key) => (data[key] ?? '').toString().toLowerCase()).join(' ');

  bool _inGroup(Map<String, dynamic> data) {
    final text = _haystack(data);
    switch (category) {
      case 'Topy':
        return RegExp(r'tri[cč]k|trick|tshirt|t-shirt|polo|tielk|tank|ko[sš]e[lľ]|shirt|mikina|hoodie|sweat|sveter|top|tricka_topy|kosele').hasMatch(text);
      case 'Nohavice':
        return RegExp(r'nohav|rifle|jean|short|kra[tť]as|pants|spodok').hasMatch(text);
      case 'Bundy':
        return RegExp(r'bund|jacket|coat|kab[aá]t|vest|outerwear').hasMatch(text);
      case 'Obuv':
        return RegExp(r'obuv|shoe|tenisk|sneaker|boot|[cč]i[zž]m|sandal').hasMatch(text);
      default:
        return RegExp(r'dopln|accessor|[cč]iap|opas|ta[sš]k|bag|hat').hasMatch(text);
    }
  }

  bool _inFilter(Map<String, dynamic> data) {
    if (filter == 'Všetko') return true;
    final text = _haystack(data);
    final terms = <String, String>{
      'Tričká': r'tri[cč]k|trick|tshirt|t-shirt',
      'Polokošele': r'polo',
      'Tielka': r'tielk|tank',
      'Košele': r'ko[sš]e[lľ]|shirt',
      'Mikiny': r'mikin|hoodie|sweatshirt',
      'Svetre': r'sveter|sweater|pullover',
      'Rifle': r'rifle|jeans',
      'Nohavice': r'nohav|pants',
      'Kraťasy': r'kra[tť]as|short',
      'Bundy': r'bund|jacket',
      'Kabáty': r'kab[aá]t|coat',
      'Vesty': r'vest',
      'Tenisky': r'tenisk|sneaker',
      'Topánky': r'top[aá]nk|shoe',
      'Čižmy': r'[cč]i[zž]m|boot',
      'Sandále': r'sandal',
      'Čiapky': r'[cč]iap|hat',
      'Opasky': r'opas|belt',
      'Tašky': r'ta[sš]k|bag',
    };
    return RegExp(terms[filter] ?? r'(?!)').hasMatch(text);
  }

  Widget _photo(Map<String, dynamic> item, {required bool center}) {
    final url = getBestWardrobeImageUrl(item);
    return SizedBox(
      width: center ? 198 : 90,
      height: center ? 254 : 185,
      child: url != null && url.isNotEmpty
          ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38)))
          : const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white38)),
    );
  }

  void _advance(int delta, int length) {
    if (length == 0) return;
    setState(() => current = (current + delta + length) % length);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Pre zobrazenie vlastného šatníka sa prihlás cez Google.')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E0D),
      appBar: AppBar(backgroundColor: const Color(0xFF0B0E0D),
        title: const Text('Môj šatník'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid)
            .collection('wardrobe').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
              child: Text('Nepodarilo sa načítať šatník: ${snapshot.error}', textAlign: TextAlign.center)));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final all = snapshot.data!.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList();
          final items = all.where((d) => _inGroup(d) && _inFilter(d)).toList();
          sortWardrobeItemsNewestFirst(items);
          if (current >= items.length) current = 0;
          return ListView(children: [
            const SizedBox(height: 14),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('KATEGÓRIE', style: TextStyle(color: gold, letterSpacing: 2))),
            const SizedBox(height: 12),
            SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal,
              children: groups.keys.map((name) => Padding(
                padding: const EdgeInsets.only(left: 10),
                child: ChoiceChip(label: Text(name), selected: category == name,
                  onSelected: (_) => setState(() { category = name; filter = 'Všetko'; current = 0; }),
                ),
              )).toList())),
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 15),
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(color: const Color(0xFF141A17),
                border: Border.all(color: const Color(0x44C8A36A)),
                borderRadius: BorderRadius.circular(22)),
              child: Column(children: [
                Text(category.toUpperCase(), style: const TextStyle(color: gold, letterSpacing: 3)),
                const SizedBox(height: 16),
                SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal,
                  children: ['Všetko', ...groups[category]!].map((name) =>
                    Padding(padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(label: Text(name), selected: filter == name,
                        onSelected: (_) => setState(() { filter = name; current = 0; })))).toList())),
                const SizedBox(height: 15),
                if (items.isEmpty)
                  const SizedBox(height: 275, child: Center(child: Text('V tejto kategórii sa nenašlo oblečenie.')))
                else GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v.abs() > 70) _advance(v < 0 ? 1 : -1, items.length);
                  },
                  child: SizedBox(height: 290, child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      Map<String, dynamic> at(int offset) => items[(current + offset + items.length) % items.length];
                      return Stack(alignment: Alignment.center, children: [
                        Positioned(left: 0, top: 45, child: Opacity(opacity: .58,
                          child: SizedBox(width: w * .24, child: _photo(at(-1), center: false)))),
                        Positioned(right: 0, top: 45, child: Opacity(opacity: .58,
                          child: SizedBox(width: w * .24, child: _photo(at(1), center: false)))),
                        Positioned(top: 0, child: GestureDetector(
                          onLongPress: () => showModalBottomSheet<void>(context: context,
                            builder: (ctx) => SafeArea(child: ListTile(
                              title: const Text('Podrobnosti (len čítanie)'),
                              subtitle: Text((at(0)['name'] ?? 'Oblečenie').toString()),
                              trailing: const Icon(Icons.lock_outline),
                            ))),
                          child: SizedBox(width: w * .53, child: _photo(at(0), center: true)))),
                      ]);
                    },
                  )),
                ),
                const SizedBox(height: 8),
                const Text('Potiahni do strán • podrž pre podrobnosti',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 20),
            const Center(child: Text('DEV • iba čítanie • bez zmien v šatníku',
              style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]);
        },
      ),
    );
  }
}
