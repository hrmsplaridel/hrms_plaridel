import 'package:hrms_plaridel/features/learning_development/models/comparative_assessment.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

/// Qualifications copied into a Selection Line-up applicant row.
class SelectionLineupApplicantFill {
  const SelectionLineupApplicantFill({
    required this.name,
    required this.education,
    required this.experience,
    required this.training,
    required this.eligibility,
  });

  final String name;
  final String education;
  final String experience;
  final String training;
  final String eligibility;
}

/// Same position matching used when HR picks a recruitment application.
String selectionLineupPositionKey(String? raw) {
  var text = (raw ?? '').trim().toLowerCase();
  text = text.replaceFirst(RegExp(r'^now hiring:\s*'), '');
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

String selectionLineupNameKey(String? raw) {
  return (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool selectionLineupSamePosition(String? a, String? b) {
  final left = selectionLineupPositionKey(a);
  final right = selectionLineupPositionKey(b);
  return left.isNotEmpty && left == right;
}

/// Fills a line-up row from the application, then from HR forms already
/// saved for that same person and vacant position.
SelectionLineupApplicantFill selectionLineupFillFromApplication({
  required RecruitmentApplication application,
  required String vacantPosition,
  List<SelectionLineupEntry> lineups = const [],
  List<ComparativeAssessmentEntry> assessments = const [],
  List<WorkExperienceSheetEntry> sheets = const [],
}) {
  final nameKey = selectionLineupNameKey(application.fullName);
  final lineupHits = <SelectionLineupApplicant>[];
  final recentLineups = [...lineups]..sort(_newerFirst);
  for (final entry in recentLineups) {
    final positionMatches = selectionLineupSamePosition(
      entry.vacantPosition,
      vacantPosition,
    );
    for (final applicant in entry.applicants) {
      final linkedId = (applicant.applicationId ?? '').trim();
      if (linkedId.isNotEmpty && linkedId == application.id) {
        lineupHits.add(applicant);
        continue;
      }
      if (linkedId.isEmpty &&
          positionMatches &&
          selectionLineupNameKey(applicant.name) == nameKey &&
          nameKey.isNotEmpty) {
        lineupHits.add(applicant);
      }
    }
  }

  final assessmentHits = <ComparativeAssessmentCandidate>[];
  final recentAssessments = [...assessments]..sort(_newerFirst);
  for (final entry in recentAssessments) {
    if (!selectionLineupSamePosition(entry.positionToBeFilled, vacantPosition)) {
      continue;
    }
    for (final candidate in entry.candidates) {
      if (selectionLineupNameKey(candidate.candidateName) == nameKey &&
          nameKey.isNotEmpty) {
        assessmentHits.add(candidate);
      }
    }
  }

  String? sheetExperience;
  final recentSheets = [...sheets]..sort(_newerFirst);
  for (final sheet in recentSheets) {
    if (!selectionLineupSamePosition(sheet.positionAppliedFor, vacantPosition)) {
      continue;
    }
    if (selectionLineupNameKey(sheet.applicantName) != nameKey ||
        nameKey.isEmpty) {
      continue;
    }
    final description = (sheet.jobDescriptionLastWork ?? '').trim();
    if (description.isNotEmpty) {
      sheetExperience = description;
      break;
    }
  }

  return SelectionLineupApplicantFill(
    name: application.fullName.trim(),
    education: _firstNonEmpty([
      for (final hit in lineupHits) hit.education,
      for (final hit in assessmentHits) hit.education,
      application.course,
    ]),
    experience: _firstNonEmpty([
      for (final hit in lineupHits) hit.experience,
      for (final hit in assessmentHits) hit.relatedExperience,
      sheetExperience,
    ]),
    training: _firstNonEmpty([
      for (final hit in lineupHits) hit.training,
      for (final hit in assessmentHits) hit.trainingHrs,
    ]),
    eligibility: _firstNonEmpty([
      for (final hit in lineupHits) hit.eligibility,
      for (final hit in assessmentHits) hit.eligibility,
    ]),
  );
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

int _newerFirst<T>(T a, T b) {
  return _updatedAt(b).compareTo(_updatedAt(a));
}

DateTime _updatedAt(dynamic entry) {
  if (entry is SelectionLineupEntry) {
    return entry.updatedAt ?? entry.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  if (entry is ComparativeAssessmentEntry) {
    return entry.updatedAt ?? entry.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  if (entry is WorkExperienceSheetEntry) {
    return entry.updatedAt ?? entry.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
