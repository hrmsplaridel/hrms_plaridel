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
}
