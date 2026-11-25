import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/wardrobe_read_only_cover_flow.dart';

/// Read-only browser preview. Uses the same Firestore wardrobe and image URLs
/// as the DEV Android build. No uploads, deletions, or background services.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Web preview only')))));
    return;
  }
  const apiKey = String.fromEnvironment('WEB_FIREBASE_API_KEY');
  const appId = String.fromEnvironment('WEB_FIREBASE_APP_ID');
  const senderId = String.fromEnvironment('WEB_FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment('WEB_FIREBASE_PROJECT_ID');
  if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty || projectId.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Firebase Web konfigurácia chýba.')))));
    return;
  }
  await Firebase.initializeApp(options: const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    authDomain: String.fromEnvironment('WEB_FIREBASE_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('WEB_FIREBASE_STORAGE_BUCKET'),
  ));
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Outfit of the Day – Wardrobe DEV',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const _PreviewGate(),
  );
}

class _PreviewGate extends StatefulWidget {
  const _PreviewGate();
  @override
  State<_PreviewGate> createState() => _PreviewGateState();
}

class _PreviewGateState extends State<_PreviewGate> {
  String? error;
  bool busy = false;

  Future<void> _signIn() async {
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasData) return const WardrobeReadOnlyCoverFlow();
      return Scaffold(
        backgroundColor: const Color(0xFF101814),
        body: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.checkroom_outlined, size: 72, color: Color(0xFFC8A36A)),
              const SizedBox(height: 20),
              const Text('Outfit of the Day – Wardrobe DEV', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23)),
              const SizedBox(height: 14),
              const Text('Skutočné fotografie z tvojho šatníka. Náhľad je iba na čítanie.',
                textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: busy ? null : _signIn,
                child: Text(busy ? 'Prihlasovanie…' : 'Prihlásiť sa cez Google')),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            ]),
          ),
        )),
      );
    },
  );
}
