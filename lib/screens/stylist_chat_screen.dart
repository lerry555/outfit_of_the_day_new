import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../Services/hourly_weather_service.dart';
import '../Services/stylist_chat_service.dart';

class StylistChatMessage {
  final String text;
  final bool isUser;
  final List<Map<String, dynamic>> suggestedItems;

  const StylistChatMessage({
    required this.text,
    required this.isUser,
    this.suggestedItems = const <Map<String, dynamic>>[],
  });
}

class StylistChatScreen extends StatefulWidget {
  final Map<String, dynamic>? initialClothingData;

  const StylistChatScreen({
    super.key,
    this.initialClothingData,
  });

  @override
  State<StylistChatScreen> createState() => _StylistChatScreenState();
}

class _StylistChatScreenState extends State<StylistChatScreen> {
  static const _accent = Color(0xFFC8A36A);
  static const _bgTop = Color(0xFF111111);
  static const _bgMid = Color(0xFF0C0C0D);
  static const _bgBottom = Color(0xFF080809);
  static const _surfaceSoft = Color(0xFF1B1B1F);
  static const _textPrimary = Color(0xFFF1F0EC);
  static const _textSecondary = Color(0xFFAAA59B);
  static const _border = Color(0x26FFFFFF);
  static const int _freeMessageLimit = 3;
  static const int _historyLimit = 8;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _stylistChatService = StylistChatService();
  final _hourlyWeatherService = HourlyWeatherService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  final List<StylistChatMessage> _messages = <StylistChatMessage>[
    const StylistChatMessage(
      text: 'Ahoj, som tvoj stylist. Napíš mi, čo chceš dnes doladiť.',
      isUser: false,
    ),
  ];

  int _userMessageCount = 0;
  bool _isPremium = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadPremiumState();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPremiumState() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      final data = snap.data();
      final status = (data?['subscriptionStatus'] ?? '').toString().toLowerCase();
      final isPremium = data?['isPremium'] == true || status == 'premium';
      if (!mounted) return;
      setState(() => _isPremium = isPremium);
    } catch (_) {
      // Keep free defaults on error.
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    if (!_isPremium && _userMessageCount >= _freeMessageLimit) {
      _showPremiumBottomSheet();
      return;
    }

    setState(() {
      _messages.add(StylistChatMessage(text: text, isUser: true));
      _controller.clear();
      _userMessageCount += 1;
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final history = _buildHistoryForBackend();
      final weatherContext = await _buildWeatherContext();
      debugPrint('STYLIST WEATHER CONTEXT: $weatherContext');
      final response = await _stylistChatService.sendMessage(
        text,
        history: history,
        weatherContext: weatherContext,
      );
      if (!mounted) return;
      final reply = (response['reply'] ?? '').toString();
      final suggestedItemsRaw = response['suggestedItems'];
      final suggestedItems = suggestedItemsRaw is List
          ? suggestedItemsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .take(4)
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      setState(() {
        _messages.add(
          StylistChatMessage(
            text: reply,
            isUser: false,
            suggestedItems: suggestedItems,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const StylistChatMessage(
            text: 'Ups, momentalne sa neviem pripojit. Skus to este raz prosim.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  Future<Map<String, dynamic>> _buildWeatherContext() async {
    final today = DateTime.now();
    final snapshot = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: 'Martin',
      date: today,
    );
    return <String, dynamic>{
      'cityName': snapshot.cityName,
      'date': snapshot.date.toIso8601String(),
      'morningTempC': snapshot.morningTempC,
      'noonTempC': snapshot.noonTempC,
      'eveningTempC': snapshot.eveningTempC,
      'minTempC': snapshot.minTempC,
      'maxTempC': snapshot.maxTempC,
      'willRain': snapshot.willRain,
      'rainTimeText': snapshot.rainTimeText,
      'isWindy': snapshot.isWindy,
      'summaryText': snapshot.summaryText,
    };
  }

  List<Map<String, String>> _buildHistoryForBackend() {
    final start = _messages.length > _historyLimit
        ? _messages.length - _historyLimit
        : 0;
    final recentMessages = _messages.sublist(start);
    return recentMessages
        .map(
          (message) => <String, String>{
            'role': message.isUser ? 'user' : 'assistant',
            'content': message.text,
          },
        )
        .toList(growable: false);
  }

  void _showPremiumBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Stylist chat je Premium',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pokračuj v konverzácii a získaj osobné odporúčania.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: const Color(0xFF191512),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text(
                      'Vyskúšať Premium',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Stylist chat',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: _textPrimary),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_bgTop, _bgMid, _bgBottom],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isSending && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      final message = _messages[index];
                      return _MessageBubble(message: message);
                    },
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          cursorColor: _accent,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Napíš správu...',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            isDense: true,
                            filled: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _isSending ? null : _sendMessage,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isSending ? _accent.withOpacity(0.45) : _accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: Color(0xFF191512),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final StylistChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    const userBg = Color(0xFFC8A36A);
    const stylistBg = Color(0xFF1B1B1F);
    const textPrimary = Color(0xFFF1F0EC);

    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? userBg : stylistBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? const Color(0xFF191512) : textPrimary,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  if (!isUser && message.suggestedItems.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: message.suggestedItems.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = message.suggestedItems[index];
                          return _SuggestedItemCard(item: item);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SuggestedItemCard({required this.item});

  String? _resolveImageUrl(Map<String, dynamic> item) {
    final candidates = [
      item['productImageUrl'],
      item['cutoutImageUrl'],
      item['cleanImageUrl'],
      item['imageUrl'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const cardBg = Color(0xFF18181B);
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label = (item['name'] ?? item['label'] ?? item['category'] ?? 'Kúsok')
        .toString();
    final imageUrl = _resolveImageUrl(item);

    return Container(
      width: 96,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 70,
              width: double.infinity,
              color: const Color(0xFF232327),
              child: imageUrl == null
                  ? const Icon(Icons.checkroom, color: textSecondary, size: 20)
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: textSecondary,
                        size: 20,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    const stylistBg = Color(0xFF1B1B1F);
    const textPrimary = Color(0xFFF1F0EC);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 280),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: stylistBg,
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Stylista píše...',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}