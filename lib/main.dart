import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Enum to describe how each date cell should be styled.
enum CalendarDateState { normal, start, end, inRange }

/// Palette for main ranges (cycled by index).
const List<Color> rangeColors = [
  Colors.blueAccent,
  Colors.green,
  Colors.orangeAccent,
  Colors.purpleAccent,
  Colors.teal,
];

/// Data model for main ranges and nested sub-ranges.
class DateRange {
  final DateTime start;
  final DateTime end;
  final List<DateRange> subRanges;
  final int colorIndex; // index into palette

  DateRange({
    required this.start,
    required this.end,
    this.subRanges = const [],
    required this.colorIndex,
  });

  DateRange copyWith({
    DateTime? start,
    DateTime? end,
    List<DateRange>? subRanges,
    int? colorIndex,
  }) {
    return DateRange(
      start: start ?? this.start,
      end: end ?? this.end,
      subRanges: subRanges ?? this.subRanges,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }

  @override
  String toString() =>
      'DateRange($start → $end, subRanges: ${subRanges.length}, colorIndex: $colorIndex)';
}

/// Styling for a single day, considering main range + sub-range.
class DayRangeStyle {
  final CalendarDateState mainState;
  final Color? mainColor;
  final CalendarDateState subState;
  final Color? subColor;

  const DayRangeStyle({
    required this.mainState,
    this.mainColor,
    required this.subState,
    this.subColor,
  });

  static const DayRangeStyle none = DayRangeStyle(
    mainState: CalendarDateState.normal,
    subState: CalendarDateState.normal,
  );
}

/// Main entry point.
void main() {
  runApp(const MyApp());
}

/// Root widget using GetMaterialApp for GetX.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Advanced Custom Calendar with GetX',
      debugShowCheckedModeBanner: false,
      home: const CalendarPage(),
    );
  }
}

/// Controller responsible for month navigation and auto-scroll while dragging.
class CalendarController extends GetxController {
  /// Current visible month (normalized to first day).
  final Rx<DateTime> currentMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  ).obs;

  DateTime get monthStart =>
      DateTime(currentMonth.value.year, currentMonth.value.month, 1);

  int _autoScrollDirection = 0; // -1 = previous month, 1 = next month, 0 = none

  void goToMonth(DateTime month) {
    currentMonth.value = DateTime(month.year, month.month, 1);
  }

  void nextMonth() {
    final m = currentMonth.value;
    currentMonth.value = DateTime(m.year, m.month + 1, 1);
  }

  void previousMonth() {
    final m = currentMonth.value;
    currentMonth.value = DateTime(m.year, m.month - 1, 1);
  }

  /// Called from drag update with global X and screen width.
  /// Decides whether to start/stop auto month scrolling.
  void updateDragPosition(double globalDx, double screenWidth) {
    const edgeThreshold = 20.0; // pixels from edge to trigger scroll
    int newDirection = 0;

    if (globalDx < edgeThreshold) {
      newDirection = -1; // scroll to previous month
    } else if (globalDx > screenWidth - edgeThreshold) {
      newDirection = 1; // scroll to next month
    }

    _setAutoScrollDirection(newDirection);
  }

  void _setAutoScrollDirection(int direction) {
    if (direction == _autoScrollDirection) return;

    _autoScrollDirection = direction;

    if (direction == 0) return;

    if (direction == -1) {
      previousMonth();
    } else if (direction == 1) {
      nextMonth();
    }
  }

  /// Called when drag ends or is canceled.
  void stopAutoScroll() {
    _autoScrollDirection = 0;
  }
}

/// Controller responsible for all range logic (multi-ranges + sub-ranges).
class RangeController extends GetxController {
  /// List of main ranges (non-overlapping, merged).
  final RxList<DateRange> ranges = <DateRange>[].obs;

  /// Start date of the current drag.
  DateTime? _dragStart;

  /// For viewing/hover effects if you want.
  final Rxn<DateTime> hoveredDate = Rxn<DateTime>();

  int _nextColorIndex = 0;

  // --- Public API ---

  void clear() {
    ranges.clear();
  }

  void startDrag(DateTime date) {
    _dragStart = _normalize(date);
  }

  void endDrag() {
    _dragStart = null;
    hoveredDate.value = null;
  }

  /// Called when a drag is dropped on a specific day.
  void handleDropOn(DateTime target) {
    final from = _dragStart;
    if (from == null) return;

    final a = _min(from, target);
    final b = _max(from, target);

    final containingA = _findContainingMainRange(a);
    final containingB = _findContainingMainRange(b);

    if (containingA != null &&
        containingB != null &&
        identical(containingA, containingB)) {
      // Drag started and ended inside the same main range → sub-range.
      _addSubRange(containingA, a, b);
    } else {
      // New main range, merge with existing.
      _addMainRange(a, b);
    }
  }

  /// Compute styling for a DateTime by looking at main ranges + sub-ranges.
  DayRangeStyle styleFor(DateTime day) {
    final d = _normalize(day);
    final mainRange = _findContainingMainRange(d);
    if (mainRange == null) {
      return DayRangeStyle.none;
    }

    // Main range styling
    final mainState = _rangeStateFor(mainRange, d);
    final baseColor = rangeColors[mainRange.colorIndex % rangeColors.length];
    Color mainColor;
    switch (mainState) {
      case CalendarDateState.start:
      case CalendarDateState.end:
        mainColor = baseColor.withValues(alpha: 0.85);
        break;
      case CalendarDateState.inRange:
        mainColor = baseColor.withValues(alpha: 0.25);
        break;
      case CalendarDateState.normal:
        mainColor = Colors.transparent;
        break;
    }

    // Sub-range styling (nested).
    final subRange = _findContainingSubRange(mainRange, d);
    CalendarDateState subState = CalendarDateState.normal;
    Color? subColor;
    if (subRange != null) {
      subState = _rangeStateFor(subRange, d);
      final subBase = baseColor; // same hue, different opacity
      switch (subState) {
        case CalendarDateState.start:
        case CalendarDateState.end:
          subColor = subBase.withValues(alpha: 0.95);
          break;
        case CalendarDateState.inRange:
          subColor = subBase.withValues(alpha: 0.6);
          break;
        case CalendarDateState.normal:
          subColor = null;
          break;
      }
    }

    return DayRangeStyle(
      mainState: mainState,
      mainColor: mainColor,
      subState: subState,
      subColor: subColor,
    );
  }

  /// Utilities: expand a DateRange to a list of DateTime (inclusive).
  List<DateTime> expandRange(DateRange r) {
    final List<DateTime> out = [];
    var day = r.start;
    while (!day.isAfter(r.end)) {
      out.add(day);
      day = day.add(const Duration(days: 1));
    }
    return out;
  }

  // --- Internal helpers ---

  void _addMainRange(DateTime start, DateTime end) {
    final normalizedStart = _normalize(start);
    final normalizedEnd = _normalize(end);

    final newRange = DateRange(
      start: normalizedStart,
      end: normalizedEnd,
      subRanges: const [],
      colorIndex: _nextColorIndex,
    );

    _nextColorIndex = (_nextColorIndex + 1) % rangeColors.length;

    final merged = _mergeRanges([...ranges, newRange]);
    ranges.assignAll(merged);
  }

  void _addSubRange(DateRange parent, DateTime start, DateTime end) {
    final parentIndex = ranges.indexOf(parent);
    if (parentIndex == -1) return;

    final normalizedStart = _normalize(start);
    final normalizedEnd = _normalize(end);

    // Clamp inside parent just in case.
    final clampedStart = _maxDate(
      normalizedStart,
      parent.start,
    ); // inside parent
    final clampedEnd = _minDate(normalizedEnd, parent.end);

    final parentRange = ranges[parentIndex];

    final newSub = DateRange(
      start: clampedStart,
      end: clampedEnd,
      subRanges: const [],
      colorIndex: parentRange.colorIndex,
    );

    final mergedSubs = _mergeRanges([...parentRange.subRanges, newSub]);
    final updatedParent = parentRange.copyWith(subRanges: mergedSubs);

    final updatedList = [...ranges];
    updatedList[parentIndex] = updatedParent;
    ranges.assignAll(updatedList);
  }

  DateRange? _findContainingMainRange(DateTime day) {
    for (final r in ranges) {
      if (_isDateInRange(day, r)) return r;
    }
    return null;
  }

  DateRange? _findContainingSubRange(DateRange parent, DateTime day) {
    for (final r in parent.subRanges) {
      if (_isDateInRange(day, r)) return r;
    }
    return null;
  }

  CalendarDateState _rangeStateFor(DateRange r, DateTime day) {
    final d = _normalize(day);
    final s = _normalize(r.start);
    final e = _normalize(r.end);

    if (_isSameDay(s, e) && _isSameDay(d, s)) {
      return CalendarDateState.start;
    }
    if (_isSameDay(d, s)) return CalendarDateState.start;
    if (_isSameDay(d, e)) return CalendarDateState.end;
    if (d.isAfter(s) && d.isBefore(e)) return CalendarDateState.inRange;
    return CalendarDateState.normal;
  }

  bool _isDateInRange(DateTime d, DateRange r) {
    final n = _normalize(d);
    return !n.isBefore(r.start) && !n.isAfter(r.end);
  }

  List<DateRange> _mergeRanges(List<DateRange> input) {
    if (input.isEmpty) return [];

    input.sort((a, b) => a.start.compareTo(b.start));
    final merged = <DateRange>[];
    var current = input.first;

    for (var i = 1; i < input.length; i++) {
      final next = input[i];
      if (_rangesOverlapOrTouch(current, next)) {
        final combined = DateRange(
          start: _minDate(current.start, next.start),
          end: _maxDate(current.end, next.end),
          colorIndex: current.colorIndex, // keep first range color
          subRanges: [...current.subRanges, ...next.subRanges],
        );
        current = combined;
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  bool _rangesOverlapOrTouch(DateRange a, DateRange b) {
    // Inclusive ranges; treat touching as mergeable.
    final aStart = a.start;
    final aEnd = a.end;
    final bStart = b.start;
    final bEnd = b.end;
    return !(aEnd.isBefore(bStart.subtract(const Duration(days: 1))) ||
        bEnd.isBefore(aStart.subtract(const Duration(days: 1))));
  }

  static DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  DateTime _minDate(DateTime a, DateTime b) => _min(a, b);

  DateTime _maxDate(DateTime a, DateTime b) => _max(a, b);
}

/// Utility helpers for calendar calculations / labels.
class DateUtilsCustom {
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Build a 6x7 grid (42 cells) for a given month,
  /// including leading/trailing days from adjacent months.
  static List<DateTime> daysInMonthGrid(DateTime monthStart) {
    final first = DateTime(monthStart.year, monthStart.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(first.year, first.month);
    final firstWeekday = first.weekday; // 1 = Monday, 7 = Sunday

    final leading = firstWeekday - 1; // 0..6

    const totalCells = 42;
    final start = first.subtract(Duration(days: leading));

    return List.generate(
      totalCells,
      (index) => DateTime(start.year, start.month, start.day + index),
    );
  }

  static const weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String monthLabel(DateTime monthStart) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[monthStart.month - 1]} ${monthStart.year}';
  }
}

/// Main calendar page.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<CalendarController>()) {
      Get.put(CalendarController());
    }
    if (!Get.isRegistered<RangeController>()) {
      Get.put(RangeController());
    }

    final calendarController = Get.find<CalendarController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Custom Calendar'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          const _MonthHeader(),
          const SizedBox(height: 8),
          const _WeekdayRow(),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(
              () => _SwipeableMonthView(
                monthStart: calendarController.monthStart,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _RangeSummary(),
          const SizedBox(height: 16),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.find<RangeController>().clear(),
        label: const Text('Clear Ranges'),
        icon: const Icon(Icons.clear_all),
      ),
    );
  }
}

/// Month header with prev/next buttons.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader();

  @override
  Widget build(BuildContext context) {
    final calendarController = Get.find<CalendarController>();

    return Obx(() {
      final monthStart = calendarController.monthStart;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: calendarController.previousMonth,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            DateUtilsCustom.monthLabel(monthStart),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: calendarController.nextMonth,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      );
    });
  }
}

/// Weekday labels row.
class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: DateUtilsCustom.weekdayLabels
          .map(
            (label) => Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Swipeable month grid with AnimatedSwitcher.
class _SwipeableMonthView extends StatelessWidget {
  final DateTime monthStart;

  const _SwipeableMonthView({required this.monthStart});

  @override
  Widget build(BuildContext context) {
    final calendarController = Get.find<CalendarController>();
    final days = DateUtilsCustom.daysInMonthGrid(monthStart);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < 0) {
          calendarController.nextMonth();
        } else if (details.primaryVelocity! > 0) {
          calendarController.previousMonth();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: GridView.builder(
          key: ValueKey<DateTime>(monthStart),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final date = days[index];
            return _DayCell(date: date);
          },
        ),
      ),
    );
  }
}

/// Single day cell with LongPressDraggable + DragTarget.
class _DayCell extends StatelessWidget {
  final DateTime date;

  const _DayCell({required this.date});

  @override
  Widget build(BuildContext context) {
    final rangeController = Get.find<RangeController>();
    final calendarController = Get.find<CalendarController>();
    final screenWidth = MediaQuery.of(context).size.width;

    return Obx(() {
      final style = rangeController.styleFor(date);
      final isToday = DateUtilsCustom.isSameDay(date, DateTime.now());
      final isCurrentMonth = DateUtilsCustom.isSameMonth(
        date,
        calendarController.monthStart,
      );

      // Main background based on main range.
      final baseRadius = BorderRadius.circular(10);

      Widget innerContent = Center(
        child: Text(
          '${date.day}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            color: isCurrentMonth ? Colors.black87 : Colors.grey,
          ),
        ),
      );

      Widget dayVisual = Container(
        decoration: BoxDecoration(
          color: style.mainColor ?? Colors.transparent,
          borderRadius: baseRadius,
        ),
        child: innerContent,
      );

      // If we are in a sub-range, draw a smaller inner container.
      if (style.subState != CalendarDateState.normal &&
          style.subColor != null) {
        dayVisual = Container(
          decoration: BoxDecoration(
            color: style.mainColor ?? Colors.transparent,
            borderRadius: baseRadius,
          ),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: style.subColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: innerContent,
            ),
          ),
        );
      }

      // Fade days outside current month.
      if (!isCurrentMonth) {
        dayVisual = Opacity(opacity: 0.4, child: dayVisual);
      }

      return DragTarget<DateTime>(
        onWillAcceptWithDetails: (draggedDate) {
          rangeController.hoveredDate.value = date;
          return true;
        },
        onLeave: (data) {
          rangeController.hoveredDate.value = null;
        },
        onAcceptWithDetails: (draggedDate) {
          rangeController.handleDropOn(date);
        },
        builder: (context, candidateData, rejectedData) {
          final isActiveTarget =
              candidateData.isNotEmpty ||
              (rangeController.hoveredDate.value != null &&
                  DateUtilsCustom.isSameDay(
                    rangeController.hoveredDate.value!,
                    date,
                  ));

          // Add border when hovered.
          final decoratedVisual = AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              borderRadius: baseRadius,
              border: isActiveTarget
                  ? Border.all(
                      color: Colors.black.withValues(alpha: .6),
                      width: 1.2,
                    )
                  : null,
            ),
            child: dayVisual,
          );

          return LongPressDraggable<DateTime>(
            data: date,
            onDragStarted: () {
              rangeController.startDrag(date);
              calendarController.stopAutoScroll();
            },
            onDragUpdate: (details) {
              calendarController.updateDragPosition(
                details.globalPosition.dx,
                screenWidth,
              );
            },
            onDragEnd: (details) {
              rangeController.endDrag();
              calendarController.stopAutoScroll();
            },
            onDraggableCanceled: (velocity, offset) {
              rangeController.endDrag();
              calendarController.stopAutoScroll();
            },
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${date.day}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: decoratedVisual),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 100),
              scale: isActiveTarget ? 1.06 : 1.0,
              child: decoratedVisual,
            ),
          );
        },
      );
    });
  }
}

/// Shows list of selected ranges and sub-ranges.
class _RangeSummary extends StatelessWidget {
  const _RangeSummary();

  @override
  Widget build(BuildContext context) {
    final rangeController = Get.find<RangeController>();

    return Obx(() {
      final list = rangeController.ranges;
      if (list.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'No ranges selected.\n'
            'Long-press a date and drag to another date to create a range.\n'
            'Dragging inside an existing range creates sub-ranges.',
            textAlign: TextAlign.center,
          ),
        );
      }

      final buffer = StringBuffer();
      for (var i = 0; i < list.length; i++) {
        final r = list[i];
        final color = rangeColors[r.colorIndex % rangeColors.length];
        buffer.writeln(
          'Range ${i + 1}: ${_fmt(r.start)} → ${_fmt(r.end)}   '
          '(sub-ranges: ${r.subRanges.length})',
        );
        for (var j = 0; j < r.subRanges.length; j++) {
          final sr = r.subRanges[j];
          buffer.writeln(
            '   - Sub ${j + 1}: ${_fmt(sr.start)} → ${_fmt(sr.end)}',
          );
        }
        buffer.writeln('   Color: ${color.toString()}');
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          buffer.toString(),
          style: const TextStyle(fontSize: 12),
          maxLines: 3,
        ),
      );
    });
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
