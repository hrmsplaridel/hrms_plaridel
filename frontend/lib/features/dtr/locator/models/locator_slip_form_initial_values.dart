class LocatorSlipFormInitialValues {
  const LocatorSlipFormInitialValues({
    this.slipDate,
    this.requestTypeCode,
    this.office,
    this.reason,
    this.amIn,
    this.amOut,
    this.pmIn,
    this.pmOut,
  });

  final DateTime? slipDate;
  final String? requestTypeCode;
  final String? office;
  final String? reason;
  final bool? amIn;
  final bool? amOut;
  final bool? pmIn;
  final bool? pmOut;

  bool get hasSlotSelection =>
      amIn != null || amOut != null || pmIn != null || pmOut != null;

  factory LocatorSlipFormInitialValues.fromActionPayload(
    Map<String, dynamic> payload,
  ) {
    DateTime? slipDate;
    for (final key in ['slipDate', 'startDate', 'endDate']) {
      final raw = payload[key];
      if (raw == null) continue;
      slipDate = DateTime.tryParse(raw.toString());
      if (slipDate != null) break;
    }

    bool? readBool(Object? value) {
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase();
      if (text == 'true' || text == '1') return true;
      if (text == 'false' || text == '0') return false;
      return null;
    }

    return LocatorSlipFormInitialValues(
      slipDate: slipDate,
      requestTypeCode: payload['locatorType']?.toString(),
      office: payload['destination']?.toString(),
      reason: payload['reason']?.toString(),
      amIn: readBool(payload['amIn']),
      amOut: readBool(payload['amOut']),
      pmIn: readBool(payload['pmIn']),
      pmOut: readBool(payload['pmOut']),
    );
  }
}
