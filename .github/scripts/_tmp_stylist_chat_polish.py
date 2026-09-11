from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected one match, got {count} for {old[:100]!r}"
        )
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# ---------------------------------------------------------------------------
# 1) Zero-token rotating welcome: useful capability hint, never model history.
# ---------------------------------------------------------------------------
Path("lib/utils/stylist_welcome_message.dart").write_text(
    """import 'dart:math';

const List<String> stylistWelcomeMessages = <String>[
  'S čím dnes pomôžem? 😊 Môžeme vyskladať outfit na konkrétnu udalosť, zhodnotiť tvoj look alebo pozrieť nové kúsky.',
  'Čo dnes riešime? 😄 Vyskladáme outfit, doladíme tvoj look alebo sa pozrieme, čo ti v šatníku chýba.',
  'Kam sa dnes chystáš? 👕 Poďme vymyslieť, čo na seba.',
  'Máš konkrétnu príležitosť alebo len chuť niečo zmeniť? 🙂 Pozrieme outfit, tvoj look aj nové kúsky.',
  'Som pripravený 😄 Môžeme riešiť outfit na udalosť, zhodnotiť to, čo máš na sebe, alebo pozrieť obchody.',
  'Čo dáme dnes? 😊 Outfit na konkrétnu akciu, rýchle hodnotenie looku alebo niečo nové do šatníka?',
  'Povedz, kam ideš alebo čo chceš doladiť 🙂 Z tvojho šatníka skúsim vybrať najlepšiu možnosť.',
  'Môžeme rovno k veci 😄 Kam ideš, čo máš na sebe alebo aký kúsok hľadáš?',
  'S čím ti dnes pomôžem? 👌 Vyskladám outfit, pozriem tvoj aktuálny look alebo môžeme hľadať nový kúsok.',
  'Čo dnes vymyslíme? 🙂 Stačí povedať príležitosť, poslať outfit na zhodnotenie alebo povedať, čo chceš dokúpiť.',
  'Outfit, hodnotenie looku alebo shopping? 😄 Povedz, čo práve potrebuješ.',
  'Poďme na to 🙂 Ak máš udalosť, plán alebo outfit na zhodnotenie, hoď ho sem.',
];

final Random _stylistWelcomeRandom = Random();

String pickStylistWelcomeMessage({Random? random}) {
  final source = random ?? _stylistWelcomeRandom;
  return stylistWelcomeMessages[source.nextInt(stylistWelcomeMessages.length)];
}

bool isStylistWelcomeMessage(String text) {
  final normalized = text.trim();
  return normalized == 'Ahoj :)' || stylistWelcomeMessages.contains(normalized);
}
""",
    encoding="utf-8",
)

screen_path = Path("lib/screens/stylist_chat_screen.dart")
screen = screen_path.read_text(encoding="utf-8")

old_import = "import '../utils/wardrobe_image_url_priority.dart';\n"
new_import = old_import + "import '../utils/stylist_welcome_message.dart';\n"
if screen.count(old_import) != 1:
    raise SystemExit("screen: wardrobe-image import anchor mismatch")
screen = screen.replace(old_import, new_import, 1)

old_greeting = (
    "  static const _greeting = StylistChatMessage(text: 'Ahoj :)', isUser: false);\n\n"
    "  final List<StylistChatMessage> _messages = <StylistChatMessage>[_greeting];"
)
new_greeting = """  final List<StylistChatMessage> _messages = <StylistChatMessage>[];

  StylistChatMessage _newWelcomeMessage() => StylistChatMessage(
    text: pickStylistWelcomeMessage(),
    isUser: false,
  );"""
if screen.count(old_greeting) != 1:
    raise SystemExit("screen: greeting anchor mismatch")
screen = screen.replace(old_greeting, new_greeting, 1)

old_init = """  void initState() {
    super.initState();
    _loadPremiumState();"""
new_init = """  void initState() {
    super.initState();
    _messages.add(_newWelcomeMessage());
    _loadPremiumState();"""
if screen.count(old_init) != 1:
    raise SystemExit("screen: initState anchor mismatch")
screen = screen.replace(old_init, new_init, 1)

if screen.count("..add(_greeting);") != 1:
    raise SystemExit(
        f"screen: reset greeting count={screen.count('..add(_greeting);')}"
    )
screen = screen.replace("..add(_greeting);", "..add(_newWelcomeMessage());", 1)

old_restore = "..addAll(loaded.isEmpty ? const [_greeting] : loaded);"
new_restore = """..addAll(
            loaded.isEmpty
                ? <StylistChatMessage>[_newWelcomeMessage()]
                : loaded,
          );"""
if screen.count(old_restore) != 1:
    raise SystemExit("screen: empty-chat restore anchor mismatch")
screen = screen.replace(old_restore, new_restore, 1)

old_persist = """              (m) =>
                  !m.ephemeral &&
                  (m.text.trim().isNotEmpty || m.imageUrl != null),"""
new_persist = """              (m) =>
                  !m.ephemeral &&
                  (m.isUser || !isStylistWelcomeMessage(m.text)) &&
                  (m.text.trim().isNotEmpty || m.imageUrl != null),"""
if screen.count(old_persist) != 1:
    raise SystemExit("screen: persistence filter anchor mismatch")
screen = screen.replace(old_persist, new_persist, 1)

old_history = """  List<Map<String, String>> _buildHistoryForBackend() {
    final start = _messages.length > _historyLimit
        ? _messages.length - _historyLimit
        : 0;
    final recentMessages = _messages.sublist(start);
    return recentMessages
"""
new_history = """  List<Map<String, String>> _buildHistoryForBackend() {
    final historyMessages = _messages
        .where(
          (message) =>
              message.isUser || !isStylistWelcomeMessage(message.text),
        )
        .toList(growable: false);
    final start = historyMessages.length > _historyLimit
        ? historyMessages.length - _historyLimit
        : 0;
    final recentMessages = historyMessages.sublist(start);
    return recentMessages
"""
if screen.count(old_history) != 1:
    raise SystemExit("screen: backend-history anchor mismatch")
screen = screen.replace(old_history, new_history, 1)
screen_path.write_text(screen, encoding="utf-8")


# ---------------------------------------------------------------------------
# 2) Wardrobe images: product -> cutout -> clean. For Storage-owned images,
#    load bytes through Firebase Storage SDK first (auth/App Check-aware), then
#    try the stored HTTP URL, then advance. Raw person originals stay excluded
#    by stylist_card_image_priority.dart.
# ---------------------------------------------------------------------------
Path("lib/widgets/stylist_suggested_item_card.dart").write_text(
    """import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../utils/stylist_card_image_priority.dart';

class StylistSuggestedItemCard extends StatefulWidget {
  const StylistSuggestedItemCard({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  State<StylistSuggestedItemCard> createState() =>
      _StylistSuggestedItemCardState();
}

class _ResolvedStylistCardImage {
  const _ResolvedStylistCardImage.memory(this.bytes) : url = null;
  const _ResolvedStylistCardImage.network(this.url) : bytes = null;

  final Uint8List? bytes;
  final String? url;
}

class _StylistSuggestedItemCardState extends State<StylistSuggestedItemCard> {
  static const int _maxStorageImageBytes = 15 * 1024 * 1024;

  late List<StylistCardImageCandidate> _candidates;
  late Future<_ResolvedStylistCardImage?> _imageFuture;
  int _index = 0;
  final Set<int> _failed = <int>{};

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant StylistSuggestedItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    const keys = <String>[
      'id',
      'productImageUrl',
      'productStoragePath',
      'cutoutImageUrl',
      'cleanImageUrl',
      'cleanStoragePath',
      'storagePath',
    ];
    final changed = keys.any((key) => oldWidget.item[key] != widget.item[key]);
    if (changed) _reset();
  }

  void _reset() {
    _index = 0;
    _failed.clear();
    _candidates = stylistCardImageCandidates(widget.item);
    _imageFuture = _resolveCurrentCandidate();
  }

  Future<_ResolvedStylistCardImage?> _resolveCurrentCandidate() async {
    if (_index < 0 || _index >= _candidates.length) return null;
    final candidate = _candidates[_index];
    final path = candidate.storagePath?.trim() ?? '';

    if (path.isNotEmpty) {
      try {
        final bytes = await FirebaseStorage.instance
            .ref(path)
            .getData(_maxStorageImageBytes)
            .timeout(const Duration(seconds: 6));
        if (bytes != null && bytes.isNotEmpty) {
          return _ResolvedStylistCardImage.memory(bytes);
        }
      } catch (_) {
        // A stored/external URL can still work. If it does not, errorBuilder
        // advances product -> cutout -> clean before showing a placeholder.
      }
    }

    final url = candidate.url.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _ResolvedStylistCardImage.network(url);
    }
    return null;
  }

  void _advanceAfterFailure(int failedIndex) {
    if (_failed.contains(failedIndex)) return;
    _failed.add(failedIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index != failedIndex) return;
      if (failedIndex + 1 < _candidates.length) {
        setState(() {
          _index = failedIndex + 1;
          _imageFuture = _resolveCurrentCandidate();
        });
      }
    });
  }

  Widget _placeholder(Color color) =>
      Icon(Icons.checkroom, color: color, size: 24);

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label = (widget.item['name'] ??
            widget.item['label'] ??
            widget.item['category'] ??
            'Kúsok')
        .toString();

    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 78,
            width: double.infinity,
            child: FutureBuilder<_ResolvedStylistCardImage?>(
              future: _imageFuture,
              builder: (context, snapshot) {
                if (_candidates.isEmpty || _index >= _candidates.length) {
                  return _placeholder(textSecondary);
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox.shrink();
                }

                final currentIndex = _index;
                final image = snapshot.data;
                if (image == null) {
                  _advanceAfterFailure(currentIndex);
                  return _placeholder(textSecondary);
                }

                final bytes = image.bytes;
                if (bytes != null) {
                  return Image.memory(
                    bytes,
                    key: ValueKey(
                      '${widget.item['id'] ?? label}:memory:$currentIndex',
                    ),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) {
                      _advanceAfterFailure(currentIndex);
                      return _placeholder(textSecondary);
                    },
                  );
                }

                final url = image.url;
                if (url == null || url.isEmpty) {
                  _advanceAfterFailure(currentIndex);
                  return _placeholder(textSecondary);
                }
                return Image.network(
                  url,
                  key: ValueKey('${widget.item['id'] ?? label}:$url'),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) {
                    _advanceAfterFailure(currentIndex);
                    return _placeholder(textSecondary);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
""",
    encoding="utf-8",
)


# ---------------------------------------------------------------------------
# 3) Zero-token greeting fast paths: warmer, still concise.
# ---------------------------------------------------------------------------
replace_once(
    "lib/Services/stylist_simple_agent_service_v1.dart",
    "reply = 'Ahoj! Jasné 🙂 S čím ti môžem pomôcť?';",
    "reply = 'Jasné 😄 Čo dnes riešime?';",
)
replace_once(
    "lib/Services/stylist_simple_agent_service_v1.dart",
    "reply = 'Ahoj! Ako ti môžem pomôcť?';",
    "reply = 'Ahoj 😊 Som tu. Čo dnes vymyslíme?';",
)


# ---------------------------------------------------------------------------
# 4) One-Brain personality: warm professional, sparse emoji, graceful garble.
# ---------------------------------------------------------------------------
prompt_path = Path("functions/stylist/v2/openai_one_brain_model_port_v2.js")
prompt = prompt_path.read_text(encoding="utf-8")
prompt_anchor = (
    '    "Odpoveď má znieť ako normálny schopný stylista, nie ako log, '
    'validator, state machine alebo technický report.",\n'
)
prompt_addition = (
    '    "Tón: priateľský profesionál — teplý, nenútený a ľudský, ale stále kompetentný. Jemne zrkadli energiu používateľa a nepreháňaj familiárnosť, ak ju používateľ sám nenastaví.",\n'
    '    "Emoji používaj striedmo a prirodzene, zvyčajne najviac jedno v odpovedi. Nemusí byť v každej správe a pri vážnom bezpečnostnom upozornení ho radšej vynechaj.",\n'
    '    "Ak je používateľ hravý alebo žartuje, môžeš odpovedať ľahkým humorom. Ak je text silno pokazený alebo preklepový a význam nevieš spoľahlivo obnoviť, povedz to ľudsky a s ľahkým humorom, že si sa trochu stratil, a popros o zopakovanie. Nepoužívaj úradnícke formulácie typu Čo presne chceš povedať alebo s čím pomôcť.",\n'
)
if prompt.count(prompt_anchor) != 1:
    raise SystemExit("one-brain: personality prompt anchor mismatch")
prompt_path.write_text(
    prompt.replace(prompt_anchor, prompt_addition + prompt_anchor, 1),
    encoding="utf-8",
)


# ---------------------------------------------------------------------------
# 5) Regressions.
# ---------------------------------------------------------------------------
fast_test_path = Path("test/stylist_simple_agent_fast_path_test.dart")
fast_test = fast_test_path.read_text(encoding="utf-8")
if not fast_test.startswith("import 'dart:io';"):
    fast_test = "import 'dart:io';\n\n" + fast_test

fast_import_anchor = (
    "import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';\n"
)
if fast_test.count(fast_import_anchor) != 1:
    raise SystemExit("fast-path test: import anchor mismatch")
fast_test = fast_test.replace(
    fast_import_anchor,
    fast_import_anchor
    + "import 'package:outfitofTheDay/utils/stylist_welcome_message.dart';\n",
    1,
)
fast_test = fast_test.replace(
    "expect(result['reply'], 'Ahoj! Ako ti môžem pomôcť?');",
    "expect(result['reply'], 'Ahoj 😊 Som tu. Čo dnes vymyslíme?');",
)
fast_test = fast_test.replace(
    "expect(result['reply'], 'Ahoj! Jasné 🙂 S čím ti môžem pomôcť?');",
    "expect(result['reply'], 'Jasné 😄 Čo dnes riešime?');",
)

widget_test_anchor = (
    "  testWidgets('shopping follow-up renders server prompt directly above yes-no buttons', (tester) async {"
)
welcome_test = """  test('new-chat welcome is varied, useful and excluded from model history', () {
    expect(stylistWelcomeMessages.length, greaterThanOrEqualTo(10));
    expect(stylistWelcomeMessages.toSet().length, stylistWelcomeMessages.length);
    expect(stylistWelcomeMessages, isNot(contains('Ahoj :)')));
    expect(isStylistWelcomeMessage('Ahoj :)'), isTrue);
    expect(
      stylistWelcomeMessages.any(
        (message) => message.toLowerCase().contains('outfit'),
      ),
      isTrue,
    );
    expect(
      stylistWelcomeMessages.any(
        (message) =>
            message.toLowerCase().contains('obchod') ||
            message.toLowerCase().contains('shopping'),
      ),
      isTrue,
    );

    final screenSource = File(
      'lib/screens/stylist_chat_screen.dart',
    ).readAsStringSync();
    expect(screenSource, contains('_newWelcomeMessage()'));
    expect(
      screenSource,
      contains('message.isUser || !isStylistWelcomeMessage(message.text)'),
    );
    expect(
      screenSource,
      isNot(contains("StylistChatMessage(text: 'Ahoj :)'")),
    );
  });

"""
if fast_test.count(widget_test_anchor) != 1:
    raise SystemExit("fast-path test: insertion anchor mismatch")
fast_test = fast_test.replace(widget_test_anchor, welcome_test + widget_test_anchor, 1)
fast_test_path.write_text(fast_test, encoding="utf-8")

image_test_path = Path("test/stylist_card_image_priority_test.dart")
image_test = image_test_path.read_text(encoding="utf-8")
if not image_test.startswith("import 'dart:io';"):
    image_test = "import 'dart:io';\n\n" + image_test
renderer_test = """
  test('Stylist card uses Storage SDK bytes before URL fallback', () {
    final source = File(
      'lib/widgets/stylist_suggested_item_card.dart',
    ).readAsStringSync();
    expect(source, contains('.getData(_maxStorageImageBytes)'));
    expect(source, contains('Image.memory('));
    expect(source, contains('Image.network('));
    expect(source, contains('_advanceAfterFailure'));
  });
"""
closing = image_test.rfind("}\n")
if closing < 0:
    raise SystemExit("image-priority test: closing brace not found")
image_test = image_test[:closing] + renderer_test + image_test[closing:]
image_test_path.write_text(image_test, encoding="utf-8")

runtime_test_path = Path("functions/stylist/v2/stylist_one_brain_runtime_v2.test.js")
runtime_test = runtime_test_path.read_text(encoding="utf-8")
enum_assertion = (
    '  assert.deepEqual(specs[0].schema.properties.pendingReplyDisposition.enum, '
    '["none", "answer", "skip", "meta", "unrelated"]);\n'
)
tone_assertions = (
    '  const systemPrompt = specs[0].messages[0].content;\n'
    '  assert.match(systemPrompt, /priateľský profesionál/);\n'
    '  assert.match(systemPrompt, /Emoji používaj striedmo/);\n'
    '  assert.match(systemPrompt, /silno pokazený alebo preklepový/);\n'
)
if runtime_test.count(enum_assertion) != 1:
    raise SystemExit("one-brain runtime test: enum assertion anchor mismatch")
runtime_test_path.write_text(
    runtime_test.replace(enum_assertion, enum_assertion + tone_assertions, 1),
    encoding="utf-8",
)
