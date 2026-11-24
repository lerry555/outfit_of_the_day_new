import 'package:flutter/material.dart';

/// Offline-only preview. This entry point does not initialize Firebase,
/// request authentication, or read/write production wardrobe data.
void main() => runApp(const DevPreviewApp());

class DevPreviewApp extends StatelessWidget {
  const DevPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Outfit of the Day DEV',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5547)),
      ),
      home: const DevPreviewHome(),
    );
  }
}

class DevPreviewHome extends StatelessWidget {
  const DevPreviewHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outfit of the Day DEV')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.checkroom_outlined, size: 76),
                const SizedBox(height: 20),
                Text('Testovacia verzia', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                  'Toto je nezavisly offline nahlad. '
                  'Nie je pripojeny k produkcnemu Firebase ani k tvojmu satniku.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.view_carousel_outlined),
                    title: Text('Wardrobe Cover Flow'),
                    subtitle: Text('Tu budeme testovat novy dizajn.'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Experiment: dev-mobile / verzia 1'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
