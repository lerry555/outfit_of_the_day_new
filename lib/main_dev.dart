import 'package:flutter/material.dart';

void main() => runApp(const WardrobePreviewApp());

const _gold = Color(0xFFC8A36A);
const _background = Color(0xFF0B0E0D);
const _panel = Color(0xFF141A17);

class WardrobePreviewApp extends StatelessWidget {
  const WardrobePreviewApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Outfit of the Day DEV',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(primary: _gold, surface: _panel),
    ),
    home: const WardrobePreview(),
  );
}

class _Piece {
  const _Piece(this.type, this.color, this.title, this.category);
  final IconData type;
  final Color color;
  final String title;
  final String category;
}

const _pieces = <_Piece>[
  _Piece(Icons.checkroom, Color(0xFFEBE8DF), 'Biele tričko', 'Tričká'),
  _Piece(Icons.checkroom, Color(0xFF25282C), 'Čierne tričko', 'Tričká'),
  _Piece(Icons.checkroom, Color(0xFF64859D), 'Modré tričko', 'Tričká'),
  _Piece(Icons.checkroom, Color(0xFFB99B70), 'Béžové polo', 'Polokošele'),
  _Piece(Icons.checkroom, Color(0xFF567063), 'Zelené polo', 'Polokošele'),
  _Piece(Icons.checkroom, Color(0xFFBDBDBD), 'Sivé tielko', 'Tielka'),
  _Piece(Icons.checkroom, Color(0xFF3E4044), 'Tmavé tielko', 'Tielka'),
];

class WardrobePreview extends StatefulWidget {
  const WardrobePreview({super.key});
  @override
  State<WardrobePreview> createState() => _WardrobePreviewState();
}

class _WardrobePreviewState extends State<WardrobePreview> {
  String _category = 'Topy';
  String _filter = 'Všetko';
  int _position = 0;
  bool _grid = false;

  List<_Piece> get _visible => _filter == 'Všetko'
      ? _pieces
      : _pieces.where((item) => item.category == _filter).toList();

  void _setFilter(String filter) => setState(() {
    _filter = filter;
    _position = 0;
  });

  void _step(int delta) {
    final items = _visible;
    if (items.isEmpty) return;
    setState(() => _position = (_position + delta + items.length) % items.length);
  }

  void _showActions(_Piece item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A201C),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(item.title, style: const TextStyle(fontSize: 18, color: _gold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Podrobnosti'),
            onTap: () {
              Navigator.pop(ctx);
              showDialog<void>(context: context, builder: (dialog) => AlertDialog(
                title: const Text('Podrobnosti – ukážka'),
                content: Text('Kúsok: ${item.title}\nPodkategória: ${item.category}\n\nÚdaje sú len demonštračné.'),
                actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Zavrieť'))],
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Zmazať'),
            onTap: () {
              Navigator.pop(ctx);
              showDialog<void>(context: context, builder: (dialog) => AlertDialog(
                title: const Text('Zmazať kúsok?'),
                content: const Text('Toto je len náhľad. Žiadne skutočné oblečenie sa nezmaže.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Zrušiť')),
                  TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Potvrdiť')),
                ],
              ));
            },
          ),
        ]),
      )),
    );
  }

  Widget _garment(_Piece item, {required bool center, double? width}) {
    return GestureDetector(
      onLongPress: () => _showActions(item),
      onTap: center ? null : () => _step(1),
      child: SizedBox(
        width: width ?? (center ? 190 : 94),
        height: center ? 252 : 194,
        child: Center(child: Icon(
          item.type,
          size: center ? 176 : 99,
          color: item.color,
          shadows: [
            Shadow(color: Colors.black.withValues(alpha: .6), blurRadius: 18, offset: const Offset(4, 12)),
            if (center) const Shadow(color: Color(0x33C8A36A), blurRadius: 26),
          ],
        )),
      ),
    );
  }

  Widget _carousel() {
    final items = _visible;
    if (items.isEmpty) return const SizedBox(height: 300, child: Center(child: Text('Žiadne kusy')));
    _Piece at(int offset) => items[(_position + offset + items.length) % items.length];
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 70) _step(velocity < 0 ? 1 : -1);
      },
      child: SizedBox(
        height: 305,
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Stack(alignment: Alignment.center, children: [
            Positioned(left: 0, top: 48, child: Opacity(opacity: .53, child: _garment(at(-1), center: false, width: w * .25))),
            Positioned(right: 0, top: 48, child: Opacity(opacity: .53, child: _garment(at(1), center: false, width: w * .25))),
            Positioned(top: 9, child: _garment(at(0), center: true, width: w * .52)),
          ]);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const categories = ['Topy', 'Nohavice', 'Bundy', 'Obuv', 'Doplnky'];
    const filters = ['Všetko', 'Tričká', 'Polokošele', 'Tielka'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _background,
        leading: const Icon(Icons.arrow_back_ios_new, size: 19),
        title: const Text('Môj šatník', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(
          tooltip: 'Mriežka',
          onPressed: () => setState(() => _grid = !_grid),
          icon: Icon(_grid ? Icons.view_carousel_outlined : Icons.grid_view_rounded, color: _gold),
        )],
      ),
      body: SafeArea(child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 22), child: Text('KATEGÓRIE', style: TextStyle(color: _gold, fontSize: 10, letterSpacing: 2.5))),
          const SizedBox(height: 10),
          SizedBox(height: 44, child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, index) {
              final cat = categories[index];
              final active = _category == cat;
              return ChoiceChip(
                label: Text(cat),
                selected: active,
                selectedColor: _gold,
                labelStyle: TextStyle(color: active ? Colors.black : Colors.white70),
                onSelected: (_) => setState(() { _category = cat; _filter = 'Všetko'; _position = 0; }),
              );
            },
          )),
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: const Color(0x2BC8A36A)),
            ),
            child: Column(children: [
              Text(_category.toUpperCase(), style: const TextStyle(color: _gold, letterSpacing: 3, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              if (_category == 'Topy') ...[
                SizedBox(height: 40, child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, index) {
                    final filter = filters[index];
                    return ChoiceChip(
                      label: Text(filter, style: const TextStyle(fontSize: 12)),
                      selected: _filter == filter,
                      selectedColor: const Color(0xFF5A4930),
                      onSelected: (_) => _setFilter(filter),
                    );
                  },
                )),
                const SizedBox(height: 8),
                if (_grid)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(spacing: 4, runSpacing: 6, children: _visible.map((piece) => GestureDetector(
                      onLongPress: () => _showActions(piece),
                      child: SizedBox(width: 100, height: 110, child: Icon(piece.type, color: piece.color, size: 88)),
                    )).toList()),
                  )
                else _carousel(),
                const SizedBox(height: 2),
                const Text('Potiahni do strán  •  podrž pre možnosti', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ] else
                const SizedBox(height: 240, child: Center(child: Text('Ďalšie kategórie pripravíme po schválení Topov.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)))),
            ]),
          ),
          const SizedBox(height: 28),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('NÁHĽAD • bez Firebase a skutočných fotografií', style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.white38))),
          const SizedBox(height: 35),
        ],
      ))),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF101512),
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Domov'),
          NavigationDestination(icon: Icon(Icons.checkroom), label: 'Šatník'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Pridať'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'Stylista'),
        ],
        onDestinationSelected: (index) {
          if (index != 1) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DEV náhľad: momentálne testujeme iba Wardrobe.')));
        },
      ),
    );
  }
}
