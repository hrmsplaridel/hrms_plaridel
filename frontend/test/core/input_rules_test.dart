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
  });
}
