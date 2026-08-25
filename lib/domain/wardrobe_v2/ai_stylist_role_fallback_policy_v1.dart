import 'ai_stylist_role_clients_v1.dart';

enum AiStylistFallbackTargetKindV1 { provider, deterministicTemplate }

class AiStylistFallbackTargetV1 {
  const AiStylistFallbackTargetV1({
    required this.kind,
    required this.provider,
    required this.modelAlias,
  });
  final AiStylistFallbackTargetKindV1 kind;
  final String provider;
  final String modelAlias;
}

class AiStylistRoleFallbackPolicyV1 {
  AiStylistRoleFallbackPolicyV1({
    required this.role,
    required Iterable<AiStylistFallbackTargetV1> targets,
  }) : targets = List.unmodifiable(targets);

  final AiStylistResponsibilityV1 role;
  final List<AiStylistFallbackTargetV1> targets;

  bool get preservesRoleAuthority => targets.isNotEmpty;
}

/// Declarative only: this policy does not invoke a provider or retry a call.
abstract final class AiStylistRoleFallbackPoliciesV1 {
  static final context = AiStylistRoleFallbackPolicyV1(
    role: AiStylistResponsibilityV1.contextClarification,
    targets: [
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.provider,
        provider: 'openai',
        modelAlias: 'gpt-4o',
      ),
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.provider,
        provider: 'anthropic',
        modelAlias: 'claude-sonnet-5',
      ),
    ],
  );
  static final finalDecision = AiStylistRoleFallbackPolicyV1(
    role: AiStylistResponsibilityV1.finalCandidateDecision,
    targets: [
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.provider,
        provider: 'openai',
        modelAlias: 'gpt-5.4-mini',
      ),
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.provider,
        provider: 'openai',
        modelAlias: 'gpt-4o',
      ),
    ],
  );
  static final explanation = AiStylistRoleFallbackPolicyV1(
    role: AiStylistResponsibilityV1.explanation,
    targets: [
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.provider,
        provider: 'anthropic',
        modelAlias: 'claude-sonnet-5',
      ),
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.provider,
        provider: 'google',
        modelAlias: 'gemini-3.5-flash',
      ),
      AiStylistFallbackTargetV1(
        kind: AiStylistFallbackTargetKindV1.deterministicTemplate,
        provider: 'local',
        modelAlias: 'deterministic_slovak_template',
      ),
    ],
  );
}
