// Philippine address helpers for cascading Province → City/Municipality → Barangay + Street.
// Nationwide PSGC dropdown data: assets/data/ph_psgc/ (see philippine_psgc_loader.dart).

/// Province name used for Misamis Occidental (must match dropdown value).
const String kProvinceMisamisOccidental = 'Misamis Occidental';

/// All Philippine provinces (common names; suitable for dropdowns).
const List<String> kPhilippineProvinces = [
  'Abra',
  'Agusan del Norte',
  'Agusan del Sur',
  'Aklan',
  'Albay',
  'Antique',
  'Apayao',
  'Aurora',
  'Basilan',
  'Bataan',
  'Batanes',
  'Batangas',
  'Benguet',
  'Biliran',
  'Bohol',
  'Bukidnon',
  'Bulacan',
  'Cagayan',
  'Camarines Norte',
  'Camarines Sur',
  'Camiguin',
  'Capiz',
  'Catanduanes',
  'Cavite',
  'Cebu',
  'Cotabato',
  'Davao de Oro',
  'Davao del Norte',
  'Davao del Sur',
  'Davao Occidental',
  'Davao Oriental',
  'Dinagat Islands',
  'Eastern Samar',
  'Guimaras',
  'Ifugao',
  'Ilocos Norte',
  'Ilocos Sur',
  'Iloilo',
  'Isabela',
  'Kalinga',
  'La Union',
  'Laguna',
  'Lanao del Norte',
  'Lanao del Sur',
  'Leyte',
  'Maguindanao del Norte',
  'Maguindanao del Sur',
  'Marinduque',
  'Masbate',
  kProvinceMisamisOccidental,
  'Misamis Oriental',
  'Mountain Province',
  'Negros Occidental',
  'Negros Oriental',
  'Northern Samar',
  'Nueva Ecija',
  'Nueva Vizcaya',
  'Occidental Mindoro',
  'Oriental Mindoro',
  'Palawan',
  'Pampanga',
  'Pangasinan',
  'Quezon',
  'Quirino',
  'Rizal',
  'Romblon',
  'Samar',
  'Sarangani',
  'Siquijor',
  'Sorsogon',
  'South Cotabato',
  'Southern Leyte',
  'Sulu',
  'Sultan Kudarat',
  'Surigao del Norte',
  'Surigao del Sur',
  'Tarlac',
  'Tawi-Tawi',
  'Zambales',
  'Zamboanga del Norte',
  'Zamboanga del Sur',
  'Zamboanga Sibugay',
];

/// Cities and municipalities in Misamis Occidental (sorted).
const List<String> misamisOccidentalCities = [
  'Aloran',
  'Baliangao',
  'Bonifacio',
  'Calamba',
  'Clarin',
  'Concepcion',
  'Don Victoriano Chiongbian',
  'Jimenez',
  'Lopez Jaena',
  'Oroquieta City',
  'Ozamiz City',
  'Panaon',
  'Plaridel',
  'Sapang Dalaga',
  'Sinacaban',
  'Tangub City',
  'Tudela',
];

/// Encodes structured parts into one DB string (pipe-separated).
String encodeStructuredAddress({
  required String street,
  required String barangay,
  required String cityMunicipality,
  required String province,
}) {
  final s = street.trim();
  final b = barangay.trim();
  final c = cityMunicipality.trim();
  final p = province.trim();
  if (s.isEmpty && b.isEmpty && c.isEmpty && p.isEmpty) return '';
  return '$s|$b|$c|$p';
}

/// Decodes [encodeStructuredAddress] output; returns null fields for legacy free-text.
({
  String street,
  String barangay,
  String city,
  String province,
  bool isStructured,
}) parseStoredAddress(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return (
      street: '',
      barangay: '',
      city: '',
      province: '',
      isStructured: false,
    );
  }
  final t = raw.trim();
  final parts = t.split('|').map((e) => e.trim()).toList();
  if (parts.length >= 4) {
    return (
      street: parts[0],
      barangay: parts[1],
      city: parts[2],
      province: parts.sublist(3).join('|'),
      isStructured: true,
    );
  }
  return (
    street: t,
    barangay: '',
    city: '',
    province: '',
    isStructured: false,
  );
}
