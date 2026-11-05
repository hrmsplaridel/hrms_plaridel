import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/utils/input_rules.dart';

void main() {
  group('InputRules person names', () {
    test('accepts letters, Ñ/ñ, spaces, hyphen, apostrophe, and periods', () {
      expect(InputRules.isValidPersonName('Juan Dela Cruz'), isTrue);
      expect(InputRules.isValidPersonName('Ñina'), isTrue);
      expect(InputRules.isValidPersonName("O'Brien"), isTrue);
      expect(InputRules.isValidPersonName('Maria-Clara'), isTrue);
      expect(InputRules.isValidPersonName('Juan Jr.'), isTrue);
      expect(InputRules.personNameError('Juan Dela Cruz'), isNull);
    });

    test('rejects digits, emoji, and empty when required', () {
      expect(InputRules.isValidPersonName('Juan2'), isFalse);
      expect(InputRules.isValidPersonName('Juan 😊'), isFalse);
      expect(InputRules.isValidPersonName(''), isFalse);
      expect(InputRules.isValidPersonName('', required: false), isTrue);
      expect(
        InputRules.personNameError('Juan 😊', label: 'First name'),
        contains('letters'),
      );
      expect(
        InputRules.personNameError('', label: 'First name'),
        'First name is required.',
      );
    });
  });

  group('InputRules email', () {
    test('accepts normal emails and rejects emoji / invalid shapes', () {
      expect(InputRules.isValidEmail('test@example.com'), isTrue);
      expect(InputRules.isValidEmail('test😊@example.com'), isFalse);
      expect(InputRules.isValidEmail('not-an-email'), isFalse);
      expect(InputRules.isValidEmail(''), isFalse);
    });
  });

  group('InputRules phone / digits', () {
    test('digitsOnly strips non-digits', () {
      expect(InputRules.digitsOnly('+63 (912) 345-6789'), '639123456789');
    });

    test('isValidPhone enforces digit length', () {
      expect(InputRules.isValidPhone('09123456789'), isTrue);
      expect(InputRules.isValidPhone('+63 912 345 6789'), isTrue);
      expect(InputRules.isValidPhone('123'), isFalse);
    });

    test('isWholeNumber', () {
      expect(InputRules.isWholeNumber('42'), isTrue);
      expect(InputRules.isWholeNumber(''), isFalse);
      expect(InputRules.isWholeNumber('', allowEmpty: true), isTrue);
      expect(InputRules.isWholeNumber('3.5'), isFalse);
    });
  });

  group('InputRules scores / helpers', () {
    test('parseScore0to100', () {
      expect(InputRules.parseScore0to100('85'), 85);
      expect(InputRules.parseScore0to100('85,5'), 85.5);
      expect(InputRules.parseScore0to100('101'), isNull);
      expect(InputRules.parseScore0to100('abc'), isNull);
    });

    test('byte helpers', () {
      expect(InputRules.formatBytesLabel(512), '512 B');
      expect(InputRules.formatBytesLabel(2048), '2.0 KB');
      expect(InputRules.formatBytesLabel(2 * 1024 * 1024), '2 MB');
      expect(InputRules.isWithinMaxBytes(100, 200), isTrue);
      expect(InputRules.isWithinMaxBytes(201, 200), isFalse);
    });
  });
}
