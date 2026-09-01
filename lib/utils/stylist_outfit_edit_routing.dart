import '../domain/wardrobe_v2/outfit_edit_plan_v1.dart';
import 'stylist_swap_request.dart';

typedef LegacyStylistSwapResolver =
    StylistSwapRequest? Function(
      Map<String, dynamic> response,
      String userText,
    );

class StylistOutfitEditRoutingV1 {
  const StylistOutfitEditRoutingV1._({
    required this.canonicalPlanPresent,
    this.canonicalPlan,
    this.legacySwap,
  });

  final bool canonicalPlanPresent;
  final OutfitEditPlanV1? canonicalPlan;
  final StylistSwapRequest? legacySwap;

  bool get canonicalPlanInvalid =>
      canonicalPlanPresent && canonicalPlan == null;

  static StylistOutfitEditRoutingV1 resolve({
    required Map<String, dynamic> response,
    required String userText,
    required LegacyStylistSwapResolver legacyResolver,
  }) {
    if (response.containsKey('outfitEditPlan')) {
      return StylistOutfitEditRoutingV1._(
        canonicalPlanPresent: true,
        canonicalPlan: OutfitEditPlanV1.tryParse(response['outfitEditPlan']),
      );
    }
    return StylistOutfitEditRoutingV1._(
      canonicalPlanPresent: false,
      legacySwap: legacyResolver(response, userText),
    );
  }
}
