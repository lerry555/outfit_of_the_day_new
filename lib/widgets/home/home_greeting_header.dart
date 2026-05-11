import 'package:flutter/material.dart';



import 'home_glass_surface.dart';

import 'home_luxury_palette.dart';



class HomeGreetingHeader extends StatelessWidget {

  const HomeGreetingHeader({

    super.key,

    required this.greetingLine,

    required this.onOpenMenu,

    this.mastheadLabel = 'OUTFIT OF THE DAY',

  });



  final String greetingLine;

  final VoidCallback onOpenMenu;

  /// Small gold label shown above the main greeting.

  final String mastheadLabel;



  @override

  Widget build(BuildContext context) {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Row(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Material(

              color: Colors.transparent,

              child: InkWell(

                onTap: onOpenMenu,

                borderRadius: BorderRadius.circular(16),

                child: HomeGlassSurface(

                  borderRadius: 16,

                  blurSigma: 12,

                  padding: const EdgeInsets.all(12),

                  child: Icon(

                    Icons.menu_rounded,

                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.95),

                    size: 24,

                  ),

                ),

              ),

            ),

            const SizedBox(width: 16),

            Expanded(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(

                    mastheadLabel,

                    style: HomeLuxuryPalette.homeGoldLabel,

                  ),

                  const SizedBox(height: 14),

                  Text(

                    greetingLine,

                    style: HomeLuxuryPalette.homeGreeting.copyWith(
                      fontSize: 34.0,
                      fontWeight: FontWeight.w600,
                    ),

                  ),

                ],

              ),

            ),

          ],

        ),

      ],

    );

  }

}

