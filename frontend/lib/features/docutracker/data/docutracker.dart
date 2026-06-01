/// DocuTracker module - Document routing and workflow tracking.
///
/// Step 1: Document Routing by Type - Each document type follows a predefined workflow.
/// Step 2: Role-Based Visibility - Employees see only documents assigned to them/office/department.
/// Step 3: Document Routing Logic - System determines next reviewer automatically.
/// Step 4: Admin Privilege Management - Per-role/per-user permissions (View, Edit, Download, etc.).
/// Step 5: Review Time Limit - sent_time, deadline_time, reviewed_time, status.

export 'docutracker_main.dart';
export 'docutracker_provider.dart';
export 'package:hrms_plaridel/features/docutracker/models/document.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_action.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_permission.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_routing_record.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
export 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
export 'package:hrms_plaridel/features/docutracker/models/escalation_config.dart';
export 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
