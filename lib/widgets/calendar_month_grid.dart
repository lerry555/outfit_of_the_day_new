import 'package:flutter/material.dart';

class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.outfitDateKeys,
    required this.onDaySelected,
  });

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Set<String> outfitDateKeys;
  final ValueChanged<DateTime> onDaySelected;

  static String dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(focusedMonth.year, focusedMonth.month, 1);

    // Monday-first calendar
    final diffToMonday = monthStart.weekday - DateTime.monday;
    final gridStart = monthStart.subtract(Duration(days: diffToMonday));

    const double cellHeight = 52.0;

    final monthEnd = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
    final totalDays = monthEnd.day;
    final usedCells = diffToMonday + totalDays;
    final rowCount = (usedCells / 7).ceil();
    final cells = rowCount * 7;

    return SizedBox(
      height: cellHeight * rowCount,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cells,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
        ),
        itemBuilder: (context, index) {
          final date = gridStart.add(Duration(days: index));
          final inMonth = date.month == monthStart.month &&
              date.year == monthStart.year;

          // mimo aktuálneho mesiaca necháme prázdne miesto
          if (!inMonth) {
            return const Padding(
              padding: EdgeInsets.all(4.0),
              child: SizedBox.expand(),
            );
          }

          final isSelected = _sameDate(date, selectedDay);
          final isToday = _sameDate(date, DateTime.now());
          final key = dateKey(date);
          final hasOutfit = outfitDateKeys.contains(key);

          final borderColor = isSelected
              ? const Color(0xFFC8A36A).withOpacity(0.65)
              : isToday
              ? const Color(0xFFC8A36A).withOpacity(0.35)
              : Colors.white.withOpacity(0.08);

          final bg = isSelected
              ? const Color(0xFFC8A36A).withOpacity(0.12)
              : isToday
              ? const Color(0xFFC8A36A).withOpacity(0.06)
              : Colors.white.withOpacity(0.07);

          final numberColor =
          isSelected ? const Color(0xFFF1F0EC) : Colors.white70;

          return Padding(
            padding: const EdgeInsets.all(4.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onDaySelected(
                  DateTime(date.year, date.month, date.day),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: bg,
                    border: Border.all(color: borderColor),
                    boxShadow: isSelected
                        ? [
                      BoxShadow(
                        color: const Color(0xFFC8A36A).withOpacity(0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                        : const [],
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 0, 0),
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: numberColor,
                              fontSize: 13,
                              fontWeight:
                              isSelected ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (hasOutfit)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.92),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withOpacity(0.18),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}