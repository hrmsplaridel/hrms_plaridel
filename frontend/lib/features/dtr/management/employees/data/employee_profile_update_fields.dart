String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String? _dateOrNull(DateTime? value) {
  if (value == null) return null;
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> buildClearableEmployeeProfileUpdateFields({
  required String middleName,
  required String? suffix,
  required String? sex,
  required DateTime? dateOfBirth,
  required String contactNumber,
  required String address,
  required String? employmentType,
  required String salaryGrade,
}) {
  return <String, dynamic>{
    'middle_name': _trimmedOrNull(middleName),
    'suffix': _trimmedOrNull(suffix),
    'sex': _trimmedOrNull(sex),
    'date_of_birth': _dateOrNull(dateOfBirth),
    'contact_number': _trimmedOrNull(contactNumber),
    'address': _trimmedOrNull(address),
    'employment_type': _trimmedOrNull(employmentType),
    'salary_grade': _trimmedOrNull(salaryGrade),
  };
}
