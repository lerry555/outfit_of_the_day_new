// lib/screens/user_preferences_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart'; // Import centralizovaných konštánt

class UserPreferencesScreen extends StatefulWidget {
  const UserPreferencesScreen({Key? key}) : super(key: key);

  @override
  _UserPreferencesScreenState createState() => _UserPreferencesScreenState();
}

class _UserPreferencesScreenState extends State<UserPreferencesScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<String> _selectedPreferredStyles = [];
  List<String> _selectedFavoriteColors = [];
  List<String> _selectedDislikedColorCombinations = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUserPreferences() async {
    if (_user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final DocumentSnapshot userDoc = await _firestore.collection('users').doc(_user!.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          // Štýly
          dynamic preferredStylesData = userData['preferredStyles'];
          if (preferredStylesData is List) {
            _selectedPreferredStyles = List<String>.from(preferredStylesData);
          } else if (preferredStylesData is String) {
            _selectedPreferredStyles = [preferredStylesData];
          } else {
            _selectedPreferredStyles = [];
          }
          _selectedPreferredStyles = _selectedPreferredStyles.where((style) => styles.contains(style)).toList();

          // Farby
          dynamic favoriteColorsData = userData['favoriteColors'];
          if (favoriteColorsData is List) {
            _selectedFavoriteColors = List<String>.from(favoriteColorsData);
          } else if (favoriteColorsData is String) {
            _selectedFavoriteColors = favoriteColorsData
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          } else {
            _selectedFavoriteColors = [];
          }
          _selectedFavoriteColors = _selectedFavoriteColors.where((color) => colors.contains(color)).toList();

          // NOVÉ: Načítanie nepovolených kombinácií farieb
          dynamic dislikedColorCombinationsData = userData['dislikedColorCombinations'];
          if (dislikedColorCombinationsData is List) {
            _selectedDislikedColorCombinations = List<String>.from(dislikedColorCombinationsData);
          } else {
            _selectedDislikedColorCombinations = [];
          }
          _selectedDislikedColorCombinations = _selectedDislikedColorCombinations.where((color) => colors.contains(color)).toList();
        });
      }
    } catch (e) {
      print('Chyba pri načítaní preferencií: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri načítaní preferencií: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveUserPreferences() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chyba: Používateľ nie je prihlásený.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _firestore.collection('users').doc(_user!.uid).set(
        {
          'favoriteColors': _selectedFavoriteColors,
          'preferredStyles': _selectedPreferredStyles,
          'dislikedColorCombinations': _selectedDislikedColorCombinations,
        },
        SetOptions(merge: true),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferencie úspešne uložené!')),
      );
    } catch (e) {
      print('Chyba pri ukladaní preferencií: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri ukladaní preferencií: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preferencie')),
        body: const Center(child: Text('Prosím, prihláste sa, aby ste spravovali preferencie.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moje Preferencie'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveUserPreferences,
          ),
        ],
      ),
      body: _isLoading && _user != null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Obľúbené farby:', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: colors.map((color) {
                final bool isSelected = _selectedFavoriteColors.contains(color);
                return FilterChip(
                  label: Text(color),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedFavoriteColors.add(color);
                      } else {
                        _selectedFavoriteColors.remove(color);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            Text('Preferované štýly:', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: styles.map((style) {
                final bool isSelected = _selectedPreferredStyles.contains(style);
                return FilterChip(
                  label: Text(style),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedPreferredStyles.add(style);
                      } else {
                        _selectedPreferredStyles.remove(style);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // NOVÉ: Farbené kombinácie, ktorým sa má vyhnúť
            Text('Farby, ktorým sa má AI vyhnúť pri kombinácii:', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: colors.map((color) {
                final bool isSelected = _selectedDislikedColorCombinations.contains(color);
                return FilterChip(
                  label: Text(color),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedDislikedColorCombinations.add(color);
                      } else {
                        _selectedDislikedColorCombinations.remove(color);
                      }
                    });
                  },
                  shape: isSelected && _selectedFavoriteColors.contains(color)
                      ? const StadiumBorder(side: BorderSide(color: Colors.red, width: 2.0))
                      : null,
                );
              }).toList(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Vyberte farby, ktoré nemá AI kombinovať s ostatnými vybranými farbami. Ak napríklad vyberiete Červenú a Oranžovú, AI sa pokúsi nekombinovať červené oblečenie s oranžovým oblečením v rovnakom outfite.',
                style: TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveUserPreferences,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Uložiť Preferencie'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}