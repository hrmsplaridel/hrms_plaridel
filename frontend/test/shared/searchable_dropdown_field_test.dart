import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/data/philippine_courses.dart';
import 'package:hrms_plaridel/shared/widgets/searchable_dropdown_field.dart';

void main() {
  test('philippine course catalog is unique and searchable by short name', () {
    expect(kPhilippineCourses.toSet().length, kPhilippineCourses.length);
    expect(
      kPhilippineCourses,
      contains('Bachelor of Science in Nursing'),
    );
    expect(
      kPhilippineCourses,
      contains('Bachelor of Science in Information Technology'),
    );
    expect(
      philippineCourseSearchText('Bachelor of Science in Nursing'),
      contains('bs'),
    );
    final sorted = [...kPhilippineCourses]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(kPhilippineCourses, sorted);
  });

  testWidgets('course field filters, selects, and keeps a typed course', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableDropdownField(
            options: kPhilippineCourses,
            value: saved,
            allowCustom: true,
            searchText: philippineCourseSearchText,
            decoration: const InputDecoration(hintText: 'Search or type a course'),
            onChanged: (value) => saved = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'bs nursing');
    await tester.pump();

    expect(find.text('Bachelor of Science in Nursing'), findsWidgets);
    expect(find.text('Bachelor of Science in Civil Engineering'), findsNothing);

    await tester.tap(find.text('Bachelor of Science in Nursing').last);
    await tester.pump();
    expect(saved, 'Bachelor of Science in Nursing');

    await tester.enterText(find.byType(TextField), 'Custom Local Course');
    await tester.pump();
    expect(saved, 'Custom Local Course');
  });

  testWidgets('dropdown arrow opens the full course list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableDropdownField(
            options: kPhilippineCourses,
            value: null,
            allowCustom: true,
            searchText: philippineCourseSearchText,
            decoration: const InputDecoration(hintText: 'Search or type a course'),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Show list'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Agricultural Crops Production NC II'), findsOneWidget);
    expect(find.text(kPhilippineCourses.first), findsOneWidget);
  });

  testWidgets('address-style field restores a value that is not in the list', (
    tester,
  ) async {
    String? saved = 'Bulacan';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SearchableDropdownField(
                options: const ['Bulacan', 'Cebu', 'Laguna'],
                value: saved,
                decoration: const InputDecoration(hintText: 'Select province'),
                onChanged: (value) => setState(() => saved = value),
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Ceb');
    await tester.pump();
    expect(find.text('Cebu'), findsWidgets);
    expect(find.text('Laguna'), findsNothing);

    await tester.tap(find.text('Cebu').last);
    await tester.pump();
    expect(saved, 'Cebu');

    await tester.enterText(find.byType(TextField), 'Not A Province');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(saved, 'Cebu');
    expect(find.text('Cebu'), findsWidgets);
  });

  test('course and strand labels stay unique and keep every college course', () {
    expect(
      kCourseOrStrandLabels.toSet().length,
      kCourseOrStrandLabels.length,
    );
    expect(
      kCourseOrStrandLabels,
      containsAll(kPhilippineCourses),
    );
    expect(
      kCourseOrStrandLabels,
      contains('Bachelor of Science in Nursing'),
    );
    expect(
      kCourseOrStrandLabels,
      contains('STEM — Science, Technology, Engineering and Mathematics'),
    );
    expect(
      kCourseOrStrandLabels,
      contains('HUMSS — Humanities and Social Sciences'),
    );
    expect(kCourseOrStrandLabels, contains('Sports Track'));
    expect(kCourseOrStrandLabels, contains('Arts and Design Track'));
    expect(
      kCourseOrStrandLabels,
      contains('TechPro — Technical-Professional Track'),
    );
    expect(
      courseOrStrandGroup('Bachelor of Science in Nursing'),
      kCourseGroupCollege,
    );
    expect(
      courseOrStrandGroup(
        'STEM — Science, Technology, Engineering and Mathematics',
      ),
      kCourseGroupShsAcademic,
    );
    expect(
      courseOrStrandGroup('TVL — Home Economics'),
      kCourseGroupShsTvl,
    );
    expect(courseOrStrandGroup('Sports Track'), kCourseGroupShsSportsArts);
    expect(
      courseOrStrandSearchText(
        'Academic Elective — Science, Technology, Engineering, and Mathematics',
      ),
      contains('stem'),
    );
    expect(
      courseOrStrandSearchText('TechPro — Technical-Professional Track'),
      contains('techpro'),
    );
  });

  testWidgets('course / strand search finds college courses and SHS options', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SearchableDropdownField(
                options: kCourseOrStrandLabels,
                value: saved,
                allowCustom: true,
                searchText: courseOrStrandSearchText,
                groupLabel: courseOrStrandGroup,
                decoration: const InputDecoration(
                  hintText: 'Search or select course / strand',
                ),
                onChanged: (value) => setState(() => saved = value),
              );
            },
          ),
        ),
      ),
    );

    Future<void> search(String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
    }

    await search('bs nursing');
    expect(find.text('Bachelor of Science in Nursing'), findsWidgets);

    await search('STEM');
    expect(
      find.text('STEM — Science, Technology, Engineering and Mathematics'),
      findsWidgets,
    );
    expect(find.text('SHS Academic Strands'), findsOneWidget);

    await search('humanities');
    expect(find.text('HUMSS — Humanities and Social Sciences'), findsWidgets);

    await search('abm');
    expect(
      find.text('ABM — Accountancy, Business and Management'),
      findsWidgets,
    );

    await search('gas');
    expect(find.text('GAS — General Academic Strand'), findsWidgets);

    await search('ict');
    expect(
      find.text('TVL — Information and Communications Technology (ICT)'),
      findsWidgets,
    );
    expect(find.text('TVL ICT — Computer Systems Servicing'), findsWidgets);

    await search('home economics');
    expect(find.text('TVL — Home Economics'), findsWidgets);

    await search('industrial arts');
    expect(find.text('TVL — Industrial Arts'), findsWidgets);

    await search('agri-fishery');
    expect(find.text('TVL — Agri-Fishery Arts'), findsWidgets);

    await search('sports track');
    expect(find.text('Sports Track'), findsWidgets);

    await search('arts and design track');
    expect(find.text('Arts and Design Track'), findsWidgets);

    await search('techpro');
    expect(find.text('TechPro — Technical-Professional Track'), findsWidgets);

    await search('stem');
    expect(
      find.text('STEM — Science, Technology, Engineering and Mathematics'),
      findsWidgets,
    );

    await search('pastry');
    expect(
      find.text('TVL Home Economics — Bread and Pastry Production'),
      findsWidgets,
    );

    await search('computer systems servicing');
    expect(find.text('Computer Systems Servicing NC II'), findsWidgets);
    expect(find.text('TVL ICT — Computer Systems Servicing'), findsWidgets);

    await search('HUMSS');
    await tester.tap(find.text('HUMSS — Humanities and Social Sciences').last);
    await tester.pump();
    expect(saved, 'HUMSS — Humanities and Social Sciences');
    expect(find.text('HUMSS — Humanities and Social Sciences'), findsWidgets);
  });
}
