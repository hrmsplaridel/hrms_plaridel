import 'package:hrms_plaridel/core/api/client.dart';

class ApprovalConfigurationRepository {
  Future<Map<String, String>> primarySummaries() async {
    final response = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/docutracker/hr-workflow-mirrors',
    );
    final workflows = rows(response.data?['workflows']);
    final leave = workflows.firstWhere((w) => w['key'] == 'leave');
    return {
      for (final step in rows(leave['steps']))
        for (final group in rows(step['groups']))
          group['scope_id']?.toString() ??
              'office-wide': group['primary'] == null
              ? 'Primary not configured'
              : 'Primary assigned',
    };
  }

  Future<List<Map<String, dynamic>>> departments() async {
    final response = await ApiClient.instance.get<List<dynamic>>(
      '/api/departments',
      queryParameters: {'status': 'Active'},
    );
    return rows(response.data);
  }

  Future<Map<String, dynamic>> reviewers(
    String? departmentId,
    String? date,
  ) async {
    final response = await ApiClient.instance.get<Map<String, dynamic>>(
      departmentId == null
          ? '/api/positions/leave-final-reviewers'
          : '/api/departments/$departmentId/reviewer-config',
      queryParameters: {if (date != null) 'effective_date': date},
    );
    return response.data!;
  }

  Future<void> saveBackups(
    String? departmentId,
    String date,
    List<String> ids,
  ) async {
    await ApiClient.instance.put<dynamic>(
      departmentId == null
          ? '/api/positions/leave-final-reviewers'
          : '/api/departments/$departmentId/reviewer-backups',
      data: {'effective_from': date, 'employee_ids': ids},
    );
  }

  Future<void> savePrimary(
    String? departmentId,
    Map<String, dynamic> values,
  ) async {
    await ApiClient.instance.put<dynamic>(
      departmentId == null
          ? '/api/positions/leave-final-reviewer-primary'
          : '/api/departments/$departmentId/reviewer-primary',
      data: values,
    );
  }

  static List<Map<String, dynamic>> rows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
}
