import '../models/leave_type.dart';

/// A single piece of guidance for a specific leave type.
class LeaveTypeGuidance {
  const LeaveTypeGuidance({
    required this.description,
    required this.requirements,
    this.limits,
    this.advanceFiling,
    this.notes,
  });

  /// Short, plain-language description of what this leave type covers.
  final String description;

  /// Summary of required supporting documents.
  final String requirements;

  /// Day limit or similar constraint (null if not applicable).
  final String? limits;

  /// Whether advance filing is typically required.
  final String? advanceFiling;

  /// Any other important reminders.
  final String? notes;
}

/// Central definition of all leave-type-specific guidance content.
///
/// Used by [LeaveTypeGuidanceCard] and [LeaveFullGuidelinesSheet].
/// Update here to propagate changes everywhere in the UI.
class LeaveGuidance {
  LeaveGuidance._();

  // ── General reminders shown at the top of the form ──────────────────────────

  static const List<String> generalReminders = [
    'Double-check your dates before submitting — corrections may require re-filing.',
    'Some leave types require attached supporting documents (e.g. medical certificate).',
    'Certain leave types have a maximum number of days allowed per year.',
    'Select a leave type first to see its specific guidelines below.',
    'Submitting does not guarantee approval — await your supervisor\'s action.',
  ];

  // ── Per-leave-type guidance ──────────────────────────────────────────────────

  static const Map<LeaveType, LeaveTypeGuidance> _guidance = {
    LeaveType.vacationLeave: LeaveTypeGuidance(
      description:
          'Granted to employees for personal recreation, rest, or travel. '
          'Must be applied for in advance and is subject to approval.',
      requirements: 'No documentary requirement. Indicate location (within Philippines or abroad).',
      advanceFiling: 'File at least 5 days before the intended leave date.',
    ),

    LeaveType.mandatoryForcedLeave: LeaveTypeGuidance(
      description:
          'All officials and employees are required to go on vacation leave for at least 5 working days annually.',
      requirements: 'No documentary requirement.',
      limits: 'Mandatory 5 working days per year (scheduled by the agency).',
      notes: 'This leave type is typically scheduled by your HR/Admin, not filed by the employee.',
    ),

    LeaveType.sickLeave: LeaveTypeGuidance(
      description:
          'Granted when an employee is unable to report due to personal illness, injury, or medical appointment.',
      requirements:
          'Medical certificate required if the absence is 5 or more consecutive days, '
          'or at the discretion of the head of office.',
      advanceFiling: 'Apply immediately upon return or during absence if possible.',
    ),

    LeaveType.maternityLeave: LeaveTypeGuidance(
      description:
          'Granted to female employees for childbirth or miscarriage, both married and unmarried.',
      requirements:
          'Medical certificate or birth/delivery record. Marriage certificate (if applicable). '
          'Notify your agency before the expected delivery.',
      limits: 'Up to 105 days; extended to 120 days for solo parents. 30-day optional extension without pay.',
      advanceFiling: 'Notify your supervisor at least 30 days before the expected delivery date.',
      notes: 'Covers normal delivery, caesarean section, and miscarriage.',
    ),

    LeaveType.paternityLeave: LeaveTypeGuidance(
      description:
          'Granted to married male employees upon the delivery/miscarriage of their legitimate spouse.',
      requirements:
          'Marriage certificate. Birth certificate or medical records showing delivery/miscarriage.',
      limits: '7 working days; must be availed within 60 days of delivery.',
      advanceFiling: 'Notify HR prior or immediately after the event.',
    ),

    LeaveType.specialPrivilegeLeave: LeaveTypeGuidance(
      description:
          'Granted for personal milestones and special occasions such as birthdays, '
          'weddings (employee or immediate family), or hospitalization of immediate family.',
      requirements: 'No documentary requirement. State location/occasion.',
      limits: '3 days per year, non-cumulative.',
      advanceFiling: 'File in advance when possible.',
    ),

    LeaveType.soloParentLeave: LeaveTypeGuidance(
      description:
          'Granted to solo parents (as defined by RA 8972) for parental obligations.',
      requirements:
          'Solo Parent ID or DSWD-issued certificate. Submit to HR before or after availing the leave.',
      limits: '7 working days per year.',
    ),

    LeaveType.studyLeave: LeaveTypeGuidance(
      description:
          'Granted to pursue higher education or review for licensure exams, '
          'with prior approval and a service obligation after completion.',
      requirements:
          'Written request citing the course/exam. School enrollment certificate or review program documents. '
          'Agency head approval required.',
      limits: 'Maximum 6 months (180 working days). Service obligation applies after.',
      advanceFiling: 'Apply well in advance — requires agency head approval.',
    ),

    LeaveType.tenDayVawcLeave: LeaveTypeGuidance(
      description:
          'Granted to women employees who are victims of Violence Against Women and Children (RA 9262) '
          'to attend to legal/medical needs.',
      requirements:
          'Barangay Protection Order, Court order, or any certified document from a government agency '
          'confirming the VAWC situation.',
      limits: '10 days per year; may be extended as deemed necessary by the agency.',
    ),

    LeaveType.rehabilitationPrivilege: LeaveTypeGuidance(
      description:
          'Granted to employees who suffered injuries while in the performance of official duties.',
      requirements:
          'Medical certificate showing the injury and its direct connection to official duties. '
          'Incident/accident report endorsed by the head of office.',
      limits: 'Up to 6 months (180 working days).',
      notes: 'Available only for work-related injuries, not personal accidents.',
    ),

    LeaveType.specialLeaveBenefitsForWomen: LeaveTypeGuidance(
      description:
          'Granted to female employees who undergo surgery caused by gynecological disorders (RA 9710).',
      requirements:
          'Medical certificate from a licensed physician confirming the gynecological disorder '
          'and the necessity of the operation.',
      limits: 'Maximum 60 days, non-cumulative.',
      advanceFiling: 'Apply before or immediately after the procedure.',
    ),

    LeaveType.specialEmergencyCalamityLeave: LeaveTypeGuidance(
      description:
          'Granted when an employee\'s place of residence is within a declared calamity area, '
          'or when the employee needs to attend to immediate family needs due to the calamity.',
      requirements:
          'Certification from the Barangay/LDRRMO or NDRRMC that the area is under calamity. '
          'Proof of residency in the affected area.',
      limits: '5 working days per calamity incident.',
    ),

    LeaveType.adoptionLeave: LeaveTypeGuidance(
      description:
          'Granted to adoptive parents upon finalization of the adoption decree (RA 8552).',
      requirements:
          'Court order / Adoption decree. Certified copy of the Certificate of Finality.',
      limits:
          '60 working days for the adoptive mother; 7 working days for the adoptive father.',
    ),

    LeaveType.others: LeaveTypeGuidance(
      description:
          'Other leave types not covered by the standard categories. '
          'Include complete details in the reason/remarks field.',
      requirements: 'Provide supporting documents as applicable to the specific circumstance.',
      notes: 'Your supervisor and HR will review and determine applicable rules.',
    ),
  };

  /// Returns the guidance for the given [leaveType], or a default message if not found.
  static LeaveTypeGuidance forType(LeaveType leaveType) {
    return _guidance[leaveType] ??
        const LeaveTypeGuidance(
          description: 'Please review the leave guidelines and provide the required information.',
          requirements: 'Attach relevant supporting documents as advised by HR.',
        );
  }

  // ── Full guidelines text (for modal/bottom-sheet viewer) ────────────────────

  static const String fullGuidelinesTitle = 'Leave Filing Guidelines';

  /// Structured sections used in the "View Full Guidelines" modal.
  static const List<LeaveGuidelineSection> fullGuidelines = [
    LeaveGuidelineSection(
      title: 'General Rules',
      icon: 'rule',
      items: [
        'All leave applications must be filed through official channels and are subject to approval by the head of office.',
        'Leave without pay (LWOP) may result in deductions from salaries and benefits.',
        'Employees must not pre-assume approval — report to duty if leave is not yet approved.',
        'Falsification of leave applications is a grave offense punishable under Civil Service rules.',
        'Leave credits are non-transferable between employees.',
      ],
    ),
    LeaveGuidelineSection(
      title: 'Filing Deadlines',
      icon: 'schedule',
      items: [
        'Vacation Leave — at least 5 days in advance.',
        'Sick Leave — upon return to duty or during absence.',
        'Maternity Leave — notify HR at least 30 days before the expected delivery.',
        'Paternity Leave — within 60 days of delivery.',
        'Special Emergency Leave — within 5 days after the calamity event.',
        'Other leave types — as soon as practicable or as indicated in agency orders.',
      ],
    ),
    LeaveGuidelineSection(
      title: 'Supporting Documents',
      icon: 'description',
      items: [
        'Sick Leave (≥5 days): Medical certificate from a licensed physician.',
        'Maternity Leave: Birth certificate, marriage certificate, medical documents.',
        'Paternity Leave: Marriage certificate, birth/delivery records.',
        'Solo Parent Leave: Solo Parent ID or DSWD certificate.',
        'Study Leave: Enrollment/registration form or review program documents.',
        'VAWC Leave: Barangay Protection Order or equivalent government-issued document.',
        'Rehabilitation Privilege: Medical certificate, incident/accident report.',
        'Special Leave for Women: Medical certificate from a licensed physician.',
        'Special Emergency Leave: Barangay/LDRRMO calamity certification.',
        'Adoption Leave: Court order, Adoption decree, Certificate of Finality.',
      ],
    ),
    LeaveGuidelineSection(
      title: 'Leave Credits & Limits',
      icon: 'event_available',
      items: [
        'Vacation Leave & Sick Leave: Earned at 1.25 days per month of service (15 days/year).',
        'Mandatory/Forced Leave: 5 working days minimum per year.',
        'Maternity Leave: 105 days (120 for solo parents). 30-day optional extension without pay.',
        'Paternity Leave: 7 working days within 60 days of delivery.',
        'Special Privilege Leave: 3 days per year, non-cumulative.',
        'Solo Parent Leave: 7 working days per year.',
        'Study Leave: Up to 6 months (180 working days). Service obligation applies.',
        'VAWC Leave: 10 working days per year.',
        'Rehabilitation Privilege: Up to 6 months (180 working days).',
        'Special Leave for Women: Up to 60 days, non-cumulative.',
        'Special Emergency Leave: Up to 5 working days per calamity.',
        'Adoption Leave: 60 days (mother), 7 days (father).',
      ],
    ),
    LeaveGuidelineSection(
      title: 'Commutation & Monetization',
      icon: 'payments',
      items: [
        'Commutation of leave credits may be requested upon retirement or separation.',
        'Terminal Leave: Commutation of accumulated vacation and sick leave credits upon retirement.',
        'Monetization: Up to 50% of accumulated leave credits may be monetized under certain conditions.',
        'For monetization or terminal leave, coordinate with HR/Finance for the computation and processing.',
      ],
    ),
  ];
}

/// Represents a section in the full leave guidelines.
class LeaveGuidelineSection {
  const LeaveGuidelineSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final String icon; // Logical name, map to IconData in the widget
  final List<String> items;
}
