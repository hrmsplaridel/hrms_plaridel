import 'package:flutter/material.dart';

class EmployeeLocatorMobileFieldLabel extends StatelessWidget {
  const EmployeeLocatorMobileFieldLabel({
    super.key,
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class EmployeeLocatorMobileLabeledField extends StatelessWidget {
  const EmployeeLocatorMobileLabeledField({
    super.key,
    required this.label,
    required this.labelColor,
    required this.child,
  });

  final String label;
  final Color labelColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmployeeLocatorMobileFieldLabel(text: label, color: labelColor),
        child,
      ],
    );
  }
}

class EmployeeLocatorMobileDateField extends StatelessWidget {
  const EmployeeLocatorMobileDateField({
    super.key,
    required this.labelColor,
    required this.dateLabel,
    required this.decoration,
    required this.onTap,
  });

  final Color labelColor;
  final String dateLabel;
  final InputDecoration decoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EmployeeLocatorMobileLabeledField(
      label: 'Date',
      labelColor: labelColor,
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: decoration.copyWith(
            suffixIcon: const Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: Color(0xFF7A7A7A),
            ),
          ),
          child: Text(dateLabel),
        ),
      ),
    );
  }
}

class EmployeeLocatorMobileFormActions extends StatelessWidget {
  const EmployeeLocatorMobileFormActions({
    super.key,
    required this.onCancel,
    required this.onSubmit,
    this.accent = const Color(0xFFF57C00),
  });

  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 40,
      children: [
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(72, 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class EmployeeLocatorMobileSegmentSelector extends StatelessWidget {
  const EmployeeLocatorMobileSegmentSelector({
    super.key,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    required this.locked,
    required this.onAmIn,
    required this.onAmOut,
    required this.onPmIn,
    required this.onPmOut,
    this.accent = const Color(0xFFF57C00),
  });

  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;
  final bool locked;
  final VoidCallback onAmIn;
  final VoidCallback onAmOut;
  final VoidCallback onPmIn;
  final VoidCallback onPmOut;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFFBEBEBE);
    const divider = Color(0xFFC9C9C9);
    return Container(
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          _SegmentCell(
            label: 'AM IN',
            selected: amIn,
            onTap: locked ? null : onAmIn,
            accent: accent,
          ),
          _SegmentDivider(divider),
          _SegmentCell(
            label: 'AM OUT',
            selected: amOut,
            onTap: locked ? null : onAmOut,
            accent: accent,
          ),
          _SegmentDivider(divider),
          _SegmentCell(
            label: 'PM IN',
            selected: pmIn,
            onTap: locked ? null : onPmIn,
            accent: accent,
          ),
          _SegmentDivider(divider),
          _SegmentCell(
            label: 'PM OUT',
            selected: pmOut,
            onTap: locked ? null : onPmOut,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _SegmentDivider extends StatelessWidget {
  const _SegmentDivider(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: color);
  }
}

class _SegmentCell extends StatelessWidget {
  const _SegmentCell({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? accent : Colors.white),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF2F2F2F),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
