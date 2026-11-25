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

class _WardrobeCoverFlowPreviewState extends State<WardrobeCoverFlowPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  double _drag = 0;
  double _settleFrom = 0;
  double _settleTo = 0;
  int _settleStep = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      if (mounted) setState(() => _drag = _settleFrom + (_settleTo - _settleFrom) * Curves.easeOutCubic.transform(_settle.value));
    });
    _settle.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() { current += _settleStep; _drag = 0; });
      }
    });
  }

  @override
  void dispose() { _settle.dispose(); super.dispose(); }

  void _dragBy(double delta, double width, int length) {
    if (length < 2) return;
    _settle.stop();
    setState(() {
      _drag += delta / (width * .48);
      while (_drag <= -1) { current++; _drag += 1; }
      while (_drag >= 1) { current--; _drag -= 1; }
    });
  }

  void _finishDrag(double velocity, int length) {
    if (length < 2) return;
    final step = _drag < -.30 || velocity < -520 ? 1 : _drag > .30 || velocity > 520 ? -1 : 0;
    _settleFrom = _drag;
    _settleStep = step;
    _settleTo = -step.toDouble();
    _settle.forward(from: 0);
  }

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
    _settle.stop(); _drag = 0; group = value; category = categories[value]!.first; subtype = 'Všetko'; current = 0;
  });
  void _switchCategory(String value) => setState(() {
    _settle.stop(); _drag = 0; category = value; subtype = 'Všetko'; current = 0;
  });

  Widget _garment(Map<String,dynamic> data, {required double width, required double height, required bool selected}) {
    // Cover Flow prioritizes the transparent cutout used on the Home outfit canvas.
    final url = getHomeOutfitImageUrlOrNull(data) ?? getBestWardrobeImageUrl(data);
    return SizedBox(
      width: width, height: height,
      child: Stack(alignment: Alignment.center, children: [
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
    return Padding(padding: const EdgeInsets.only(right: 5),
      child: InkWell(onTap: () => _switchCategory(value),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(duration: const Duration(milliseconds: 180),
          width: 69, padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3C321C) : const Color(0xFF151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? gold : const Color(0xFF35302A), width: active ? 1.7 : 1),
            boxShadow: active ? [BoxShadow(color: gold.withOpacity(.24), blurRadius: 16)] : [],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: active ? gold : Colors.white70, size: 23),
            const SizedBox(height: 5),
            Text(value, maxLines: 2, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: active ? gold : Colors.white, height: 1.1)),
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
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(children: [
          const Icon(Icons.arrow_back_ios_new, color: gold, size: 18),
          const Expanded(child: Column(children: [
            Text('O U T F I T   O F   T H E   D A Y', style: TextStyle(color: gold, fontSize: 9, letterSpacing: 1.1)),
            SizedBox(height: 7),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.checkroom_outlined, color: gold, size: 30),
              SizedBox(width: 8),
              Text('Môj šatník', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
          ])),
          IconButton(onPressed: () => showDialog<void>(context: context,
            builder: (ctx) => AlertDialog(title: const Text('Cover Flow'),
              content: const Text('Náhľad používa skutočný šatník. Úpravy sú vypnuté.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))])),
            icon: const Icon(Icons.info_outline, color: gold)),
        ]),
      ),
      Container(margin: const EdgeInsets.symmetric(horizontal: 14), height: 49,
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
      const SizedBox(height: 14),
      SizedBox(height: 78, child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
                  final h = size.maxHeight.clamp(180.0, 580.0).toDouble();
                  Map<String,dynamic> at(int offset) => items[(idx + offset + items.length) % items.length];
                  // Five virtual positions form a continuous circular carousel.
                  // Every pointer movement changes the positions and sizes immediately.
                  final slots = <int>[-2, -1, 1, 2, 0];
                  final ordered = slots.toList()..sort((a, b) =>
                    (b + _drag).abs().compareTo((a + _drag).abs()));
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _settle.stop(),
                    onHorizontalDragUpdate: (d) => _dragBy(d.delta.dx, width, items.length),
                    onHorizontalDragEnd: (d) => _finishDrag(d.primaryVelocity ?? 0, items.length),
                    onHorizontalDragCancel: () => _finishDrag(0, items.length),
                    onLongPress: () => _showDetail(at(0)),
                    child: ClipRect(child: SizedBox.expand(child: Stack(alignment: Alignment.center,
                      children: [
                        // Full-bleed scene glow, not a narrow rectangular shadow behind one item.
                        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -.06),
                            radius: 1.05,
                            colors: [gold.withOpacity(.25), const Color(0xFF19150F), background],
                            stops: const [0, .55, 1],
                          ),
                        ))),
                        ...ordered.where((slot) => items.length > 2 || slot.abs() <= 1).map((slot) {
                        final position = slot + _drag;
                        final distance = position.abs();
                        final scale = (1 - distance * .23).clamp(.42, 1.0);
                        final opacity = (1 - (distance - 1).clamp(0.0, 1.0) * .75).clamp(.2, 1.0);
                        final x = position * width * .36;
                        return Transform.translate(
                          key: ValueKey('cover-$slot'),
                          offset: Offset(x, distance * h * .045),
                          child: Opacity(opacity: opacity,
                            child: Transform.scale(scale: scale,
                              child: _garment(at(slot), width: width * .80,
                                height: h * .84, selected: distance < .45))),
                        );
                      }).toList(),
                      ],
                    ))),
                  );
                })),
            Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 15),
              child: Row(children: [
                if (category == 'Tričká & topy') Expanded(child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: Row(children: ['Všetko','Tričká','Polokošele','Tielka'].map((value) {
                    final active = subtype == value;
                    return Padding(padding: const EdgeInsets.only(right: 3),
                      child: ChoiceChip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(horizontal: -3, vertical: -2),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                        label: Text(value, style: TextStyle(fontSize: 11, color: active ? Colors.black : Colors.white70)),
                        selected: active, selectedColor: gold, backgroundColor: surface,
                        side: BorderSide(color: active ? gold : const Color(0xFF4B4030)),
                        onSelected: (_) => setState(() { _settle.stop(); _drag = 0; subtype = value; current = 0; }),
                      ));
                  }).toList())))
                else const Spacer(),
                const SizedBox(width: 2),
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
