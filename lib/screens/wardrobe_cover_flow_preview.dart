import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/wardrobe_image_processing.dart';
import '../utils/wardrobe_image_url_priority.dart';
import '../utils/wardrobe_list_utils.dart';

/// Read-only Cover Flow preview using the August black-and-gold palette.
/// No Firestore or Storage writes.
class WardrobeCoverFlowPreview extends StatefulWidget {
  const WardrobeCoverFlowPreview({super.key});
  @override
  State<WardrobeCoverFlowPreview> createState() => _WardrobeCoverFlowPreviewState();
}

class _WardrobeCoverFlowPreviewState extends State<WardrobeCoverFlowPreview> {
  static const gold = Color(0xFFC8A36A);
  static const background = Color(0xFF090909);
  static const surface = Color(0xFF181716);
  static const categories = <String, List<String>>{
    'Oblečenie': ['Tričká & topy', 'Košele', 'Mikiny', 'Svetre', 'Bundy & kabáty', 'Nohavice'],
    'Obuv': ['Tenisky', 'Topánky', 'Čižmy', 'Sandále'],
    'Doplnky': ['Čiapky', 'Opasky', 'Tašky'],
  };
  String group = 'Oblečenie';
  String category = 'Tričká & topy';
  String subtype = 'Všetko';
  int current = 0;

  String _s(Map<String, dynamic> d, String key) => (d[key] ?? '').toString().toLowerCase();
  String _combined(Map<String, dynamic> d) => [
    'categoryKey','subCategoryKey','categoryLabel','subCategoryLabel','name','category','mainGroup'
  ].map((k) => _s(d,k)).join(' ');

  bool _belongs(Map<String,dynamic> d) {
    final key = _s(d,'categoryKey');
    final main = _s(d,'mainGroup');
    final t = _combined(d);
    if (group == 'Obuv' && main.isNotEmpty && main != 'obuv') return false;
    if (group == 'Doplnky' && main.isNotEmpty && main != 'doplnky') return false;
    if (group == 'Oblečenie' && main.isNotEmpty && main != 'oblecenie') return false;
    switch (category) {
      case 'Tričká & topy': return key == 'tricka_topy' || RegExp(r'tri[cč]k|trick|tielk|tank|polo|t-shirt|tshirt').hasMatch(t);
      case 'Košele': return key == 'kosele' || RegExp(r'ko[sš]e[lľ]|kosel').hasMatch(t);
      case 'Mikiny': return key == 'mikiny' || RegExp(r'mikin|hoodie|sweatshirt').hasMatch(t);
      case 'Svetre': return key == 'svetre' || RegExp(r'sveter|sweater|pullover').hasMatch(t);
      case 'Bundy & kabáty': return key == 'bundy_kabaty' || RegExp(r'bund|jacket|kab[aá]t|coat').hasMatch(t);
      case 'Nohavice': return key == 'nohavice_rifle' || RegExp(r'nohav|rifle|jeans|pants').hasMatch(t);
      case 'Tenisky': return key == 'tenisky' || RegExp(r'tenisk|sneaker').hasMatch(t);
      case 'Topánky': return RegExp(r'top[aá]nk|shoe').hasMatch(t);
      case 'Čižmy': return key == 'cizmy' || RegExp(r'[cč]i[zž]m|boot').hasMatch(t);
      case 'Sandále': return RegExp(r'sandal').hasMatch(t);
      case 'Čiapky': return RegExp(r'[cč]iap|hat').hasMatch(t);
      case 'Opasky': return RegExp(r'opas|belt').hasMatch(t);
      case 'Tašky': return RegExp(r'ta[sš]k|bag').hasMatch(t);
      default: return false;
    }
  }

  int _typeRank(Map<String,dynamic> d) {
    final t = _combined(d);
    if (RegExp(r'tri[cč]k|trick|t-shirt|tshirt').hasMatch(t)) return 0;
    if (t.contains('polo')) return 1;
    if (RegExp(r'tielk|tank').hasMatch(t)) return 2;
    return 3;
  }

  bool _subtypeMatch(Map<String,dynamic> d) {
    if (subtype == 'Všetko') return true;
    final rank = _typeRank(d);
    return subtype == 'Tričká' ? rank == 0 : subtype == 'Polokošele' ? rank == 1 : rank == 2;
  }

  void _switchGroup(String value) => setState(() {
    group = value; category = categories[value]!.first; subtype = 'Všetko'; current = 0;
  });
  void _switchCategory(String value) => setState(() {
    category = value; subtype = 'Všetko'; current = 0;
  });

  Widget _garment(Map<String,dynamic> data, {required double width, required double height, required bool selected}) {
    final url = getBestWardrobeImageUrl(data);
    return SizedBox(
      width: width, height: height,
      child: Stack(alignment: Alignment.center, children: [
        if (selected) Container(
          margin: const EdgeInsets.all(18),
          decoration: BoxDecoration(boxShadow: [
            BoxShadow(color: gold.withOpacity(.36), blurRadius: 38, spreadRadius: 12),
          ]),
        ),
        if (url.isNotEmpty) Positioned.fill(child: wardrobeItemImage(
          data: data, imageUrl: url, showSpinner: false,
          backgroundColor: Colors.transparent, fit: BoxFit.contain,
        )),
        if (url.isEmpty) const Icon(Icons.image_not_supported_outlined, color: Colors.white30),
      ]),
    );
  }

  void _showDetail(Map<String,dynamic> data) {
    showModalBottomSheet<void>(context: context, backgroundColor: surface,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((data['name'] ?? 'Oblečenie').toString(), style: const TextStyle(color: Colors.white, fontSize: 21)),
          const SizedBox(height: 12),
          const Text('Podrobnosti • testovací náhľad iba na čítanie', style: TextStyle(color: gold)),
          const SizedBox(height: 16),
          const Text('Mazanie a úpravy sú v tomto náhľade vypnuté.', style: TextStyle(color: Colors.white70)),
        ]),
      )));
  }

  Widget _categoryButton(String value) {
    final active = value == category;
    final icon = value.contains('Tričká') ? Icons.checkroom_outlined
      : value == 'Košele' ? Icons.dry_cleaning_outlined
      : value == 'Nohavice' ? Icons.airline_seat_legroom_normal
      : value == 'Tenisky' ? Icons.hiking_outlined : Icons.checkroom_outlined;
    return Padding(padding: const EdgeInsets.only(right: 10),
      child: InkWell(onTap: () => _switchCategory(value),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(duration: const Duration(milliseconds: 180),
          width: 98, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3C321C) : const Color(0xFF151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? gold : const Color(0xFF35302A), width: active ? 1.7 : 1),
            boxShadow: active ? [BoxShadow(color: gold.withOpacity(.24), blurRadius: 16)] : [],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: active ? gold : Colors.white70, size: 28),
            const SizedBox(height: 8),
            Text(value, maxLines: 2, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: active ? gold : Colors.white, height: 1.15)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Prihlás sa cez Google.'));
    return ColoredBox(color: background, child: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Row(children: [
          const Icon(Icons.arrow_back_ios_new, color: gold, size: 20),
          const Expanded(child: Column(children: [
            Text('O U T F I T   O F   T H E   D A Y', style: TextStyle(color: gold, fontSize: 10, letterSpacing: 1.3)),
            SizedBox(height: 7),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.checkroom_outlined, color: gold, size: 30),
              SizedBox(width: 8),
              Text('Môj šatník', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.bold)),
            ]),
          ])),
          IconButton(onPressed: () => showDialog<void>(context: context,
            builder: (ctx) => AlertDialog(title: const Text('Cover Flow'),
              content: const Text('Náhľad používa skutočný šatník. Úpravy sú vypnuté.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))])),
            icon: const Icon(Icons.info_outline, color: gold)),
        ]),
      ),
      Container(margin: const EdgeInsets.symmetric(horizontal: 14), height: 54,
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(27),
          border: Border.all(color: const Color(0xFF3D3223))),
        child: Row(children: categories.keys.map((name) {
          final active = name == group;
          return Expanded(child: InkWell(onTap: () => _switchGroup(name),
            borderRadius: BorderRadius.circular(27),
            child: Container(alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                color: active ? const Color(0xFF49391F) : Colors.transparent,
                border: active ? Border.all(color: gold, width: 1.5) : null,
                boxShadow: active ? [BoxShadow(color: gold.withOpacity(.22), blurRadius: 15)] : null),
              child: Text(name, style: TextStyle(color: active ? gold : Colors.white70,
                fontSize: 14, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
            )));
        }).toList()),
      ),
      const SizedBox(height: 18),
      SizedBox(height: 104, child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: categories[group]!.map(_categoryButton).toList())),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('wardrobe').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Chyba načítania: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: gold));
          final items = snapshot.data!.docs.map((d) => <String,dynamic>{...d.data(), 'id': d.id})
            .where(_belongs).where(_subtypeMatch).toList();
          sortWardrobeItemsNewestFirst(items);
          if (category == 'Tričká & topy' && subtype == 'Všetko') {
            items.sort((a,b) => _typeRank(a).compareTo(_typeRank(b)));
          }
          final idx = items.isEmpty ? 0 : current % items.length;
          return Column(children: [
            Expanded(child: items.isEmpty
              ? const Center(child: Text('V tejto kategórii nemáš oblečenie.', style: TextStyle(color: Colors.white60)))
              : LayoutBuilder(builder: (context, size) {
                  final width = size.maxWidth;
                  final h = size.maxHeight.clamp(180.0, 470.0).toDouble();
                  Map<String,dynamic> at(int offset) => items[(idx + offset + items.length) % items.length];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() > 65) setState(() => current = (idx + (v < 0 ? 1 : items.length - 1)) % items.length);
                    },
                    onLongPress: () => _showDetail(at(0)),
                    child: Stack(alignment: Alignment.center, children: [
                      Positioned(left: -width * .035, child: Opacity(opacity: .78,
                        child: _garment(at(-1), width: width * .36, height: h * .72, selected: false))),
                      Positioned(right: -width * .035, child: Opacity(opacity: .78,
                        child: _garment(at(1), width: width * .36, height: h * .72, selected: false))),
                      _garment(at(0), width: width * .59, height: h * .92, selected: true),
                    ]),
                  );
                })),
            Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
              child: Row(children: [
                if (category == 'Tričká & topy') Expanded(child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: Row(children: ['Všetko','Tričká','Polokošele','Tielka'].map((value) {
                    final active = subtype == value;
                    return Padding(padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(value, style: TextStyle(fontSize: 12, color: active ? Colors.black : Colors.white70)),
                        selected: active, selectedColor: gold, backgroundColor: surface,
                        side: BorderSide(color: active ? gold : const Color(0xFF4B4030)),
                        onSelected: (_) => setState(() { subtype = value; current = 0; }),
                      ));
                  }).toList()))
                else const Spacer(),
                const SizedBox(width: 6),
                IconButton(onPressed: () => showModalBottomSheet<void>(context: context,
                  isScrollControlled: true, backgroundColor: surface,
                  builder: (ctx) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(ctx).height * .65,
                    child: GridView.builder(padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .8),
                      itemCount: items.length,
                      itemBuilder: (_, i) => InkWell(onTap: () {
                        Navigator.pop(ctx); setState(() => current = i);
                      }, child: _garment(items[i], width: 110, height: 150, selected: false)))))),
                  icon: const Icon(Icons.grid_view_rounded, color: gold)),
              ])),
          ]);
        },
      )),
    ])));
  }
}
