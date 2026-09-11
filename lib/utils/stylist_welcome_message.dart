import 'dart:math';

const List<String> stylistWelcomeMessages = <String>[
  'S čím dnes pomôžem? 😊 Môžeme vyskladať outfit na konkrétnu udalosť, zhodnotiť tvoj look alebo pozrieť nové kúsky.',
  'Čo dnes riešime? 😄 Vyskladáme outfit, doladíme tvoj look alebo sa pozrieme, čo ti v šatníku chýba.',
  'Kam sa dnes chystáš? 👕 Poďme vymyslieť, čo na seba.',
  'Máš konkrétnu príležitosť alebo len chuť niečo zmeniť? 🙂 Pozrieme outfit, tvoj look aj nové kúsky.',
  'Som pripravený 😄 Môžeme riešiť outfit na udalosť, zhodnotiť to, čo máš na sebe, alebo pozrieť obchody.',
  'Čo dáme dnes? 😊 Outfit na konkrétnu akciu, rýchle hodnotenie looku alebo niečo nové do šatníka?',
  'Povedz, kam ideš alebo čo chceš doladiť 🙂 Z tvojho šatníka skúsim vybrať najlepšiu možnosť.',
  'Môžeme rovno k veci 😄 Kam ideš, čo máš na sebe alebo aký kúsok hľadáš?',
  'S čím ti dnes pomôžem? 👌 Vyskladám outfit, pozriem tvoj aktuálny look alebo môžeme hľadať nový kúsok.',
  'Čo dnes vymyslíme? 🙂 Stačí povedať príležitosť, poslať outfit na zhodnotenie alebo povedať, čo chceš dokúpiť.',
  'Outfit, hodnotenie looku alebo shopping? 😄 Povedz, čo práve potrebuješ.',
  'Poďme na to 🙂 Ak máš udalosť, plán alebo outfit na zhodnotenie, hoď ho sem.',
];

final Random _stylistWelcomeRandom = Random();

String pickStylistWelcomeMessage({Random? random}) {
  final source = random ?? _stylistWelcomeRandom;
  return stylistWelcomeMessages[source.nextInt(stylistWelcomeMessages.length)];
}

bool isStylistWelcomeMessage(String text) {
  final normalized = text.trim();
  return normalized == 'Ahoj :)' || stylistWelcomeMessages.contains(normalized);
}
