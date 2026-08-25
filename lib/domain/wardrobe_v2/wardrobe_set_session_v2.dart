import 'wardrobe_set_v2.dart';

class WardrobeSetSessionV2 {
  const WardrobeSetSessionV2({
    required this.draftId,
    required this.components,
    this.inferenceCount = 0,
    this.retryCount = 0,
  });
  final String draftId;
  final List<WardrobeSetDraftComponentV2> components;
  final int inferenceCount, retryCount;

  WardrobeSetSessionV2 update(
    WardrobeSetDraftComponentV2 component, {
    bool inferenceStarted = false,
    bool retry = false,
  }) {
    final next = [...components];
    final index = next.indexWhere(
      (item) => item.componentId == component.componentId,
    );
    if (index < 0) {
      next.add(component);
    } else {
      next[index] = component;
    }
    return WardrobeSetSessionV2(
      draftId: draftId,
      components: next,
      inferenceCount: inferenceCount + (inferenceStarted ? 1 : 0),
      retryCount: retryCount + (retry ? 1 : 0),
    );
  }

  int get savedCount => components
      .where(
        (component) => component.status == WardrobeSetComponentStatusV2.saved,
      )
      .length;
  bool get canComplete => savedCount >= 2;

  bool shouldRunInference(String componentId) {
    final component = components
        .where((item) => item.componentId == componentId)
        .firstOrNull;
    if (component == null) return true;
    return component.cachedAnalyzerPayload == null &&
        component.status != WardrobeSetComponentStatusV2.analysisReady &&
        component.status != WardrobeSetComponentStatusV2.saving &&
        component.status != WardrobeSetComponentStatusV2.saved;
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': '1.0.0',
    'draftId': draftId,
    'components': components.map((component) => component.toMap()).toList(),
    'inferenceCount': inferenceCount,
    'retryCount': retryCount,
    'savedCount': savedCount,
    'status': canComplete ? 'ready_to_complete' : 'incomplete',
  };
}
