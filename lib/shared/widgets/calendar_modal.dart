import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UniversalCalendarModal extends StatefulWidget {
  final DateTime? initialDate;
  const UniversalCalendarModal({super.key, this.initialDate});

  @override
  State<UniversalCalendarModal> createState() => _UniversalCalendarModalState();
}

class _UniversalCalendarModalState extends State<UniversalCalendarModal> {
  late DateTime _focusedDate;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _focusedDate = widget.initialDate ?? DateTime.now();
    _selectedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildDayHeaders(),
            _buildCalendarGrid(),
            const Divider(height: 32),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          DateFormat('MMMM, yyyy').format(_focusedDate),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
        ),
        const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black),
        const Spacer(),
        IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
          onPressed: () => setState(() => _focusedDate = DateTime(_focusedDate.year, _focusedDate.month - 1)),
        ),
        const SizedBox(width: 8),
        IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
          onPressed: () => setState(() => _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + 1)),
        ),
      ],
    );
  }

  Widget _buildDayHeaders() {
    final days = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days.map((day) => Expanded(
        child: Center(
          child: Text(day, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.black54)),
        ),
      )).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_focusedDate.year, _focusedDate.month, 1);
    final lastDayOfMonth = DateTime(_focusedDate.year, _focusedDate.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday % 7;

    final prevMonthLastDay = DateTime(_focusedDate.year, _focusedDate.month, 0).day;
    
    List<Widget> dayWidgets = [];

    // Previous month days
    for (int i = 0; i < firstWeekday; i++) {
      final dayNum = prevMonthLastDay - firstWeekday + i + 1;
      dayWidgets.add(_buildDayCell(dayNum, isCurrentMonth: false));
    }

    // Current month days
    for (int i = 1; i <= daysInMonth; i++) {
      dayWidgets.add(_buildDayCell(i, isCurrentMonth: true));
    }

    // Next month days to fill the grid (6 rows total = 42 cells)
    int totalCells = 42;
    int nextMonthDays = totalCells - dayWidgets.length;
    for (int i = 1; i <= nextMonthDays; i++) {
      dayWidgets.add(_buildDayCell(i, isCurrentMonth: false));
    }

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 7,
      physics: const NeverScrollableScrollPhysics(),
      children: dayWidgets,
    );
  }

  Widget _buildDayCell(int day, {required bool isCurrentMonth}) {
    bool isSelected = false;
    if (isCurrentMonth && _selectedDate != null) {
      isSelected = _selectedDate!.day == day && 
                   _selectedDate!.month == _focusedDate.month && 
                   _selectedDate!.year == _focusedDate.year;
    }

    return GestureDetector(
      onTap: () {
        if (isCurrentMonth) {
          setState(() => _selectedDate = DateTime(_focusedDate.year, _focusedDate.month, day));
          Navigator.pop(context, _selectedDate);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF007AFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              color: isSelected ? Colors.white : (isCurrentMonth ? Colors.black : Colors.grey.shade300),
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Clear', style: TextStyle(color: Color(0xFF007AFF))),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _focusedDate = DateTime.now();
              _selectedDate = DateTime.now();
            });
            Navigator.pop(context, _selectedDate);
          },
          child: const Text('Today', style: TextStyle(color: Color(0xFF007AFF))),
        ),
      ],
    );
  }
}
