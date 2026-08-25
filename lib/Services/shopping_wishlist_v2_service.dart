import 'package:cloud_functions/cloud_functions.dart';

import '../screens/shopping/shopping_candidate_ui.dart';

abstract interface class ShoppingWishlistV2Gateway {
  Future<Map<String, dynamic>> save(ShoppingWishlistIntent intent);
  Future<Map<String, dynamic>> update(ShoppingWishlistIntent intent);
  Future<void> remove(String variantId);
  Future<List<Map<String, dynamic>>> getItems();
  Future<Map<String, dynamic>> refreshAll({String? operationId});
  Future<Map<String, dynamic>> refreshItem(String wishlistItemId);
  Future<Map<String, dynamic>> acknowledge(List<String> wishlistItemIds);
}

class ShoppingWishlistV2Service implements ShoppingWishlistV2Gateway {
  ShoppingWishlistV2Service({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-east1');

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> save(ShoppingWishlistIntent intent) async {
    final result = await _call(<String, dynamic>{
      'operation': 'ADD_OR_UPSERT',
      'variantId': intent.variantId,
      'selectedSizes': intent.selectedSizes.toList(growable: false),
      'preferredSize': intent.preferredSize,
      'targetPrice': {
        'amountMinor': intent.targetAmountMinor,
        'currency': intent.currency,
      },
      'priceMonitoringEnabled': intent.priceMonitoringEnabled,
      'sizeMonitoringEnabled': intent.sizeMonitoringEnabled,
    });
    return _map(result['item']);
  }

  @override
  Future<Map<String, dynamic>> update(ShoppingWishlistIntent intent) async {
    final result = await _call(<String, dynamic>{
      'operation': 'UPDATE_INTENT',
      'variantId': intent.variantId,
      'selectedSizes': intent.selectedSizes.toList(growable: false),
      'preferredSize': intent.preferredSize,
      'targetPrice': {
        'amountMinor': intent.targetAmountMinor,
        'currency': intent.currency,
      },
      'priceMonitoringEnabled': intent.priceMonitoringEnabled,
      'sizeMonitoringEnabled': intent.sizeMonitoringEnabled,
    });
    return _map(result['item']);
  }

  @override
  Future<void> remove(String variantId) async {
    await _call(<String, dynamic>{
      'operation': 'REMOVE',
      'variantId': variantId,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getItems() async {
    final result = await _call(<String, dynamic>{'operation': 'GET_ITEMS'});
    final values = result['items'];
    return values is List ? values.map(_map).toList(growable: false) : const [];
  }

  @override
  Future<Map<String, dynamic>> refreshAll({String? operationId}) async {
    return _call(<String, dynamic>{
      'operation': 'REFRESH_ALL',
      if (operationId != null) 'operationId': operationId,
    });
  }

  @override
  Future<Map<String, dynamic>> refreshItem(String wishlistItemId) async {
    return _call(<String, dynamic>{
      'operation': 'REFRESH_ITEM',
      'wishlistItemId': wishlistItemId,
    });
  }

  @override
  Future<Map<String, dynamic>> acknowledge(List<String> wishlistItemIds) async {
    return _call(<String, dynamic>{
      'operation': 'ACKNOWLEDGE_HIGHLIGHTS',
      'wishlistItemIds': wishlistItemIds,
    });
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final response = await _functions
        .httpsCallable('shoppingWishlistV2')
        .call<Map<String, dynamic>>(payload);
    return _map(response.data);
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
}

class ShoppingCandidateDetailsService {
  ShoppingCandidateDetailsService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-east1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> get({
    required String sessionId,
    required String variantId,
  }) async {
    final response = await _functions
        .httpsCallable('shoppingCandidateDetails')
        .call<Map<String, dynamic>>(<String, dynamic>{
          'sessionId': sessionId,
          'variantId': variantId,
        });
    return Map<String, dynamic>.from(response.data);
  }
}
