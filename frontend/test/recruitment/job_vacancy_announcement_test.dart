import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';

void main() {
  test('hiring closed unless a job title is actually listed', () {
    const closedToggle = JobVacancyAnnouncement(hasVacancies: false);
    expect(closedToggle.isAcceptingApplications, isFalse);

    const openWithoutTitle = JobVacancyAnnouncement(
      hasVacancies: true,
      vacancies: [
        JobVacancyItem(
          education: 'BSIT',
          experience: '1 year',
          training: 'CSC',
        ),
      ],
    );
    expect(openWithoutTitle.listedVacancies, isEmpty);
    expect(openWithoutTitle.isAcceptingApplications, isFalse);

    const openWithTitle = JobVacancyAnnouncement(
      hasVacancies: true,
      vacancies: [JobVacancyItem(headline: 'Administrative Aide')],
    );
    expect(openWithTitle.isAcceptingApplications, isTrue);
    expect(openWithTitle.listedVacancies.single.hasListedPosition, isTrue);
  });

  test('has_vacancies defaults to closed when missing or malformed', () {
    final missing = JobVacancyAnnouncement.fromJson({});
    expect(missing.hasVacancies, isFalse);

    final asString = JobVacancyAnnouncement.fromJson({
      'has_vacancies': 'false',
    });
    expect(asString.hasVacancies, isFalse);

    final asTrue = JobVacancyAnnouncement.fromJson({'has_vacancies': true});
    expect(asTrue.hasVacancies, isTrue);
  });

  test('age requirements default to 18 and round-trip on save', () {
    const created = JobVacancyItem(headline: 'Administrative Aide');
    expect(created.minimumAge, 18);
    expect(created.maximumAge, isNull);
    expect(created.ageRequirementLabel, '18 years old and above');

    final parsed = JobVacancyAnnouncement.fromJson({
      'has_vacancies': true,
      'vacancies': [
        {'headline': 'Work Immersion', 'minimum_age': 15},
        {
          'headline': 'HR Assistant',
          'minimum_age': 18,
          'maximum_age': 30,
        },
        {'headline': 'Existing vacancy'},
      ],
    });
    expect(parsed.vacancies[0].ageRequirementLabel, '15 years old and above');
    expect(parsed.vacancies[0].maximumAge, isNull);
    expect(parsed.vacancies[1].ageRequirementLabel, '18–30 years old');
    expect(parsed.vacancies[2].minimumAge, 18);
    expect(parsed.vacancies[2].maximumAge, isNull);

    final saved = parsed.toJson();
    final vacancies = saved['vacancies'] as List;
    expect(vacancies[0]['minimum_age'], 15);
    expect(vacancies[0]['maximum_age'], isNull);
    expect(vacancies[1]['maximum_age'], 30);

    expect(
      JobVacancyItem.ageOnDate(DateTime(2010, 10, 10), DateTime(2026, 10, 10)),
      16,
    );
    expect(
      JobVacancyItem.ageOnDate(DateTime(2010, 10, 11), DateTime(2026, 10, 10)),
      15,
    );
    expect(
      JobVacancyItem.ageOnDate(DateTime(2008, 10, 10), DateTime(2026, 10, 10)),
      18,
    );
  });
}
