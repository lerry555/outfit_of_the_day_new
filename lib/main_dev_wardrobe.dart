import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'screens/wardrobe_read_only_cover_flow.dart';

/// DEV only: does not bootstrap the production app, background services,
/// analytics, upload triggers or any write-capable wardrobe UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const WardrobeDevApp());
}

class WardrobeDevApp extends StatelessWidget {
  const WardrobeDevApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Outfit of the Day DEV',
    theme: ThemeData.dark(useMaterial3: true),
    home: const WardrobeDevGate(),
  );
}

class WardrobeDevGate extends StatefulWidget {
  const WardrobeDevGate({super.key});
  @override
  State<WardrobeDevGate> createState() => _WardrobeDevGateState();
}

class _WardrobeDevGateState extends State<WardrobeDevGate> {
  bool busy = false;
  String? error;

  Future<void> signIn() async {
    setState(() { busy = true; error = null; });
    try {
      final account = await GoogleSignIn().signIn();
      if (account == null) return;
      final auth = await account.authentication;
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          accessToken: auth.accessToken,
          idToken: auth.idToken,
        ),
      );
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
      if (snapshot.data != null) return const WardrobeReadOnlyCoverFlow();
      return Scaffold(
        backgroundColor: const Color(0xFF0B0E0D),
        appBar: AppBar(title: const Text('Outfit of the Day DEV')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.checkroom_outlined, size: 72, color: Color(0xFFC8A36A)),
            const SizedBox(height: 20),
            const Text('Tvoj skutočný šatník', style: TextStyle(fontSize: 23)),
            const SizedBox(height: 12),
            const Text('Testovací Wardrobe – iba čítanie. Prihlás sa tým istým Google účtom ako v pôvodnej aplikácii.', textAlign: TextAlign.center),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy ? null : signIn,
              child: Text(busy ? 'Prihlasovanie…' : 'Prihlásiť cez Google'),
            ),
            if (error != null) ...[
              const SizedBox(height: 18),
              SelectableText(error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ]),
        )),
      );
    },
  );
}
