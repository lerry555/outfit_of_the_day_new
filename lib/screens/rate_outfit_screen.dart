// lib/screens/rate_outfit_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class RateOutfitScreen extends StatefulWidget {
  const RateOutfitScreen({Key? key}) : super(key: key);

  @override
  State<RateOutfitScreen> createState() => _RateOutfitScreenState();
}

class _RateOutfitScreenState extends State<RateOutfitScreen> {
  File? _selectedOutfitImage;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile =
    await picker.pickImage(source: source, imageQuality: 85);

    if (pickedFile != null) {
      setState(() {
        _selectedOutfitImage = File(pickedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ohodnoť môj outfit'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chceš vedieť, ako ti to pristane?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Odfoti sa alebo vyber fotku z galérie. Neskôr sem doplníme AI hodnotenie (skóre + tipy).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: () => _pickImage(ImageSource.camera),
                    label: const Text('Odfotiť'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: () => _pickImage(ImageSource.gallery),
                    label: const Text('Z galérie'),
                  ),
                ),
              ],
            ),
            if (_selectedOutfitImage != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _selectedOutfitImage!,
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'AI analýza outfitu (skóre + tipy) doplníme v ďalšom kroku.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
