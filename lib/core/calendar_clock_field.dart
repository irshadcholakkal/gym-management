import 'package:flutter/material.dart';

/// Picker-only input. Stored dates remain YYYY-MM-DD and times remain HH:mm.
class CalendarClockField extends StatefulWidget {
  const CalendarClockField({
    super.key,
    required this.controller,
    required this.label,
    this.time = false,
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool time;
  final bool enabled;
  final FormFieldValidator<String>? validator;

  @override
  State<CalendarClockField> createState() => _CalendarClockFieldState();
}

class _CalendarClockFieldState extends State<CalendarClockField> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking || !widget.enabled) return;
    _picking = true;
    try {
      String? value;
      if (widget.time) {
        final parts = widget.controller.text.split(':');
        final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
        final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
        final selected = await showTimePicker(
          context: context,
          initialTime: hour != null &&
                  minute != null &&
                  hour >= 0 &&
                  hour < 24 &&
                  minute >= 0 &&
                  minute < 60
              ? TimeOfDay(hour: hour, minute: minute)
              : TimeOfDay.now(),
          initialEntryMode: TimePickerEntryMode.dialOnly,
          helpText: widget.label,
        );
        if (selected != null) {
          value =
              '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
        }
      } else {
        final current = DateTime.tryParse(widget.controller.text) ??
            DateTime.now().toUtc().add(const Duration(hours: 4));
        final selected = await showDatePicker(
          context: context,
          initialDate: DateUtils.dateOnly(current),
          firstDate: DateTime(current.year < 1900 ? current.year : 1900),
          lastDate: DateTime(current.year > 2100 ? current.year : 2100, 12, 31),
          initialEntryMode: DatePickerEntryMode.calendarOnly,
          helpText: widget.label,
        );
        if (selected != null) {
          value =
              '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
        }
      }
      if (mounted && widget.enabled && value != null) {
        widget.controller.text = value;
      }
    } finally {
      _picking = false;
    }
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        enabled: widget.enabled,
        readOnly: true,
        showCursor: false,
        onTap: _pick,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.time ? 'Select time' : 'Select date',
          suffixIcon: IconButton(
            tooltip: widget.time ? 'Open clock' : 'Open calendar',
            onPressed: widget.enabled ? _pick : null,
            icon: Icon(widget.time
                ? Icons.schedule_rounded
                : Icons.calendar_month_rounded),
          ),
        ),
      );
}
