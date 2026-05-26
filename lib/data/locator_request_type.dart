enum LocatorRequestType {
  locator(
    code: 'locator',
    label: 'Locator / Official Business',
    shortLabel: 'Locator',
    locationLabel: 'Office / Destination',
    locationHint: 'Enter office or destination',
    dtrSlotLabel: 'On Field',
    dtrPrintLabel: 'ON FIELD',
  ),
  passSlip(
    code: 'pass_slip',
    label: 'Pass Slip',
    shortLabel: 'Pass Slip',
    locationLabel: 'Destination / Location',
    locationHint: 'Enter destination or location',
    dtrSlotLabel: 'Pass Slip',
    dtrPrintLabel: 'PASS SLIP',
  ),
  workFromHome(
    code: 'work_from_home',
    label: 'Work From Home',
    shortLabel: 'WFH',
    locationLabel: 'Work Location',
    locationHint: 'Enter work location',
    dtrSlotLabel: 'WFH',
    dtrPrintLabel: 'WFH',
  );

  const LocatorRequestType({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.locationLabel,
    required this.locationHint,
    required this.dtrSlotLabel,
    required this.dtrPrintLabel,
  });

  final String code;
  final String label;
  final String shortLabel;
  final String locationLabel;
  final String locationHint;
  final String dtrSlotLabel;
  final String dtrPrintLabel;

  static LocatorRequestType fromCode(Object? value) {
    final code = value?.toString().trim().toLowerCase();
    for (final type in LocatorRequestType.values) {
      if (type.code == code) return type;
    }
    return LocatorRequestType.locator;
  }
}
