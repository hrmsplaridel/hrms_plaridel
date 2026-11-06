import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/utils/input_rules.dart';

void main() {
  group('InputRules plain text / emoji', () {
    test('rejects emoji and pictographs', () {
      expect(InputRules.containsForbiddenGlyphs('Hello 😀'), isTrue);
      expect(InputRules.isValidPlainText('Hello 😀'), isFalse);
      expect(
        InputRules.plainTextError('Hello 😀', label: 'Title'),
        contains('emoji'),
      );
      expect(InputRules.containsForbiddenGlyphs('Province 🏠'), isTrue);
      expect(InputRules.stripForbiddenGlyphs('Hi 😀 there'), 'Hi  there');
    });

    test('allows business text with Ñ and punctuation', () {
      const sample = "Brgy. San Jose, Plaridel - Unit 2B (near school's gate)";
      expect(InputRules.containsForbiddenGlyphs(sample), isFalse);
      expect(InputRules.isValidPlainText(sample), isTrue);
      expect(InputRules.plainTextError(sample, label: 'Address'), isNull);
    });

    test('person names still reject digits and emoji', () {
      expect(InputRules.isValidPersonName('Juan 😊'), isFalse);
      expect(InputRules.isValidPersonName('Juan Dela Cruz'), isTrue);
      expect(InputRules.isValidPersonName('Ñina'), isTrue);
    });

    test('email rejects emoji', () {
      expect(InputRules.isValidEmail('test😊@example.com'), isFalse);
      expect(InputRules.isValidEmail('test@example.com'), isTrue);
    });

    test('plainTextFormatters and merge default to no-emoji', () {
      expect(InputRules.plainTextFormatters(), isNotEmpty);
      expect(InputRules.noEmojiFormatters, isNotEmpty);
      expect(InputRules.merge(null), isNotEmpty);
      expect(InputRules.merge(const []), isNotEmpty);
    });
  });

  group('InputRules helpers', () {
    test('personNameError and empty rules', () {
      expect(InputRules.isValidPersonName(''), isFalse);
      expect(InputRules.isValidPersonName('', required: false), isTrue);
      expect(
        InputRules.personNameError('', label: 'First name'),
        'First name is required.',
      );
      expect(InputRules.isValidPersonName("O'Brien"), isTrue);
      expect(InputRules.isValidPersonName('Juan Jr.'), isTrue);
    });

    test('digitsOnly / phone / whole number', () {
      expect(InputRules.digitsOnly('+63 (912) 345-6789'), '639123456789');
      expect(InputRules.isValidPhone('09123456789'), isTrue);
      expect(InputRules.isValidPhone('123'), isFalse);
      expect(InputRules.isWholeNumber('42'), isTrue);
      expect(InputRules.isWholeNumber('3.5'), isFalse);
    });

    test('parseScore0to100 and byte helpers', () {
      expect(InputRules.parseScore0to100('85'), 85);
      expect(InputRules.parseScore0to100('85,5'), 85.5);
      expect(InputRules.parseScore0to100('101'), isNull);
      expect(InputRules.formatBytesLabel(512), '512 B');
      expect(InputRules.isWithinMaxBytes(100, 200), isTrue);
      expect(InputRules.isWithinMaxBytes(201, 200), isFalse);
    });
  });
}
