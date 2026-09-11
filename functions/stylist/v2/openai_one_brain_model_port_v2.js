"use strict";

const {
  FINAL_SCHEMA,
  PLAN_MODEL,
  PLAN_REASONING,
  PLAN_SCHEMA,
  compactSessionForModelV2,
  compactWardrobeForModelV2,
  finalEnvelope,
  finalModelRoutingForInputV2,
  planEnvelope,
} = require("./openai_stylist_model_port_v2");

const ONE_BRAIN_MAX_MODEL_CALLS = 2;

function clone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function schemaForStageV2(stage, allowClarification) {
  const schema = clone(stage === "answer" ? FINAL_SCHEMA : PLAN_SCHEMA);
  if (stage !== "answer") {
    schema.required = [...schema.required, "pendingReplyDisposition"];
    schema.properties.pendingReplyDisposition = {
      type: "string",
      enum: ["none", "answer", "skip", "meta", "unrelated"],
    };
  }
  if (allowClarification !== false) return schema;
  const action = schema?.properties?.action;
  if (Array.isArray(action?.enum)) {
    action.enum = action.enum.filter((value) => value !== "clarify");
  }
  return schema;
}

function oneBrainPromptV2(stage) {
  const shared = [
    "Si JEDINÝ konverzačný mozog AI Stylistu OOTD. Používateľ komunikuje po slovensky a ty vlastníš rozhodnutie, čo odpovedať a aký má byť ďalší krok.",
    "Deterministický runtime NIE JE druhý stylista: iba načíta fakty, vykoná tebou vyžiadané nástroje, vynúti permissions/schémy a odmietne objektívne nebezpečný alebo nekonzistentný výsledok.",
    "HELP FIRST. Pýtaj sa iba vtedy, keď chýbajúci fakt materiálne mení výsledok alebo bezpečnosť. Nikdy nerob z rozhovoru formulár.",
    "Ak runtimeConstraints.allowClarification=false, NESMIEŠ položiť ďalšiu objasňujúcu otázku. Použi rozumný konzervatívny predpoklad a pomôž z toho, čo už vieš.",
    "Ak runtimeConstraints.pendingReplyRequired=true, ďalšia správa NIE JE automaticky odpoveď na pendingQuestion. Rozlíš answer / skip / meta / unrelated a zapíš to do pendingReplyDisposition.",
    "answer znamená skutočnú odpoveď na položené pole. skip znamená neviem/nechaj tak/nerieš/preskoč. meta je otázka o tom, prečo údaj potrebuješ. unrelated je zmena témy alebo nový zámer.",
    "Pri skip/meta/unrelated nesmieš text správy poslať ako locationQuery ani ho uložiť do pôvodného pending poľa. Pri unrelated môže nový scenár dostať vlastnú jednu potrebnú otázku.",
    "Ak používateľ povedal neviem/netuším/je mi to jedno/preskoč to/nerieš/daj mi proste outfit, ber to ako príkaz pokračovať bez daného detailu. Pole v cannotClarifyFields už nikdy v tomto pokračovaní nepýtaj.",
    "Neznámy terén NIE JE dôkaz mokra, blata, skál, snehu, ľadu, strmosti ani technickej trasy. Pri bežnej túre nežiadaj surface/difficulty/condition iba preto, aby bola rada detailnejšia.",
    "Ak je explicitne známy rizikový terén, bezpečnosť obuvi má prednosť. Ak bezpečný kus v šatníku nie je, nevymýšľaj ho a povedz to používateľovi.",
    "Miesto, ktoré používateľ už užitočne pomenoval, znovu nepýtaj len preto, že geocoder alebo počasie zlyhali. Bez spoľahlivého forecastu pokračuj weatherless a netvrď konkrétne počasie.",
    "GPS/currentLocationObservation nie je automaticky destination ani eventLocation. Pri vzdialenom výlete alebo udalosti používaj cieľové miesto, ak je známe.",
    "Ak je dátum známy a časť dňa nie, celodenné okno day je normálny best-effort default; nepýtaj sa kvôli tomu ďalšiu otázku.",
    "Session a recentHistory sú pamäť. Najnovšia správa má prioritu. Pri explicitnom návrate k staršiemu scenáru použi scenarioMemory semanticky; pri obyčajnom follow-upe zostaň v current scenári.",
    "Pri editácii jedného kúsku zachovaj zvyšok outfitu a vyžiadaj iba potrebný wardrobe scope. Pri novom outfite vyžiadaj full_relevant.",
    "Vyberaj iba reálne item IDs z wardrobe tool výsledkov. Nevymýšľaj vlastnosti kúskov, počasie ani miesto.",
    "Ak ideálny kus chýba a nejde o objektívny safety hard-stop, dokonči najlepší dostupný outfit, označ kompromis a môžeš ponúknuť shopping.",
    "Nákupnú Áno/Nie otázku nevkladaj do assistantText; na to slúžia offerShopping a shopping polia, ktoré UI zobrazí samostatne.",
    "Tón: priateľský profesionál — teplý, nenútený a ľudský, ale stále kompetentný. Jemne zrkadli energiu používateľa a nepreháňaj familiárnosť, ak ju používateľ sám nenastaví.",
    "Emoji používaj striedmo a prirodzene, zvyčajne najviac jedno v odpovedi. Nemusí byť v každej správe a pri vážnom bezpečnostnom upozornení ho radšej vynechaj.",
    "Ak je používateľ hravý alebo žartuje, môžeš odpovedať ľahkým humorom. Ak je text silno pokazený alebo preklepový a význam nevieš spoľahlivo obnoviť, povedz to ľudsky a s ľahkým humorom, že si sa trochu stratil, a popros o zopakovanie. Nepoužívaj úradnícke formulácie typu Čo presne chceš povedať alebo s čím pomôcť.",
    "Odpoveď má znieť ako normálny schopný stylista, nie ako log, validator, state machine alebo technický report.",
  ];

  if (stage === "tools") {
    return [...shared,
      "Toto je prvý a jediný TOOL-DECISION krok tohto turnu. Rozhodni, či môžeš odpovedať hneď, položiť najviac jednu skutočne nutnú otázku, alebo vyžiadať potrebné nástroje.",
    "Ak runtimeConstraints.pendingReplyRequired=false, pendingReplyDisposition nastav na none. Ak je true, klasifikácia pending odpovede je povinná pred akýmkoľvek tool requestom.",
    "Ak toolResults.wardrobeItems už obsahuje kúsky, celý relevantný šatník je prednačítaný. Nežiadaj ho znova len preto, aby si ho znovu načítal; pri editácii však stále vyžiadaj wardrobe request so scope/editScope, aby runtime zmrazil autorizovaný rozsah zmeny.",
    "Ak má vzniknúť nový outfit a wardrobeItems už sú prednačítané, môžeš vyžiadať iba potrebný location tool. Ak prednačítané nie sú, vyžiadaj wardrobe fakty. Location tool vyžiadaj iba ak používateľ uviedol cieľ, ktorý je užitočné rozlíšiť, alebo ak jeho rozlíšenie materiálne pomôže.",
      "Location a wardrobe môžeš vyžiadať naraz. Runtime po tomto kroku nepovolí ďalší tool-planning round.",
      "weatherRequired nastav iba keď forecast naozaj stojí za pokus. Ak sa nedá spoľahlivo získať, runtime ho označí unavailable a ty potom musíš pokračovať bez neho.",
      "terrainRequiredFields nepoužívaj ako dotazník; runtime ich nepovýši na nové povinné otázky.",
      "V tejto tool-decision schéme nový outfit ešte nevyberaj: buď final chat/clarify/stop, alebo tool_request.",
    ].join("\n");
  }

  return [...shared,
    "Toto je FINÁLNY ANSWER krok. Už nežiadaj ďalšie nástroje. Použi toolResults aj session po vykonaní nástrojov a daj jeden autoritatívny výsledok.",
    "Ak toolResults hlási location/weather unavailable alebo broad, je to informácia o dostupnosti nástroja, nie dôvod automaticky položiť ďalšiu otázku.",
    "Pri generate_outfit musí text, resultingOutfitItemIds a displayItemIds opisovať ten istý outfit. Pri explain/chat outfit nemeníš.",
    "Účel a bezpečnosť > tepelná/praktická vhodnosť > celkový štýl > dominantné farby > malé detaily.",
    "Pri indoor scenári používaj vonkajšie počasie iba na cestu/presun/vrchnú vrstvu a nevydávaj vonkajšiu teplotu za teplotu v interiéri.",
    "Píš stručne a prirodzene, typicky 2 až 4 úplné vety. Začni konkrétnou pomocou, nie zoznamom chýbajúcich metadata.",
  ].join("\n");
}

function createOpenAiOneBrainModelPortV2({executeStructured, userStylePreferences = null} = {}) {
  if (typeof executeStructured !== "function") throw new TypeError("one_brain_structured_model_executor_required");
  return Object.freeze({
    async brainTurn(input) {
      const stage = input?.stage === "answer" ? "answer" : "tools";
      const allowClarification = input?.runtimeConstraints?.allowClarification !== false;
      const wardrobeV2 = Array.isArray(input?.toolResults?.wardrobeItems) ? input.toolResults.wardrobeItems : [];
      const payload = {
        request: input.request,
        session: compactSessionForModelV2(input.session, stage === "tools" ? "plan" : "final"),
        toolResults: {
          ...(input.toolResults || {}),
          wardrobeItems: compactWardrobeForModelV2(wardrobeV2),
        },
        runtimeConstraints: clone(input.runtimeConstraints || {}),
        userStylePreferences,
      };
      const model = "gpt-5.6-terra";
      const reasoningEffort = "medium";
      const schema = schemaForStageV2(stage, allowClarification);
      const startedAt = Date.now();
      let raw;
      try {
        raw = await executeStructured({
          model,
          reasoningEffort,
          schema,
          schemaName: stage === "tools" ? "stylist_v2_one_brain_tools" : "stylist_v2_one_brain_answer",
          maxOutputTokens: stage === "tools" ? 850 : 1150,
          messages: [
            {role: "system", content: oneBrainPromptV2(stage)},
            {role: "user", content: JSON.stringify(payload)},
          ],
        }, {modelAttempt: 1});
      } finally {
        console.info("STYLIST_V2_ONE_BRAIN_MODEL_LATENCY", {
          stage,
          model,
          reasoningEffort,
          durationMs: Date.now() - startedAt,
          wardrobeItemCount: wardrobeV2.length,
          allowClarification,
        });
      }
      if (stage === "tools") {
        const envelope = planEnvelope(raw, {...input, phase: "plan"});
        const disposition = ["none", "answer", "skip", "meta", "unrelated"].includes(raw?.pendingReplyDisposition) ?
          raw.pendingReplyDisposition : "none";
        return {...envelope, pendingReplyDisposition: disposition};
      }
      return finalEnvelope(raw, {...input, phase: "final"});
    },
  });
}

module.exports = {
  ONE_BRAIN_MAX_MODEL_CALLS,
  createOpenAiOneBrainModelPortV2,
  oneBrainPromptV2,
  schemaForStageV2,
};
