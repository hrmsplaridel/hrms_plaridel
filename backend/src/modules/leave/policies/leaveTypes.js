'use strict';
module.exports = function createLeaveComponent({
  BALANCE_LEDGER_CONFIG_TYPES,
  CREDIT_BALANCE_BUCKET_TYPES,
  LEAVE_TYPE_RULES,
  LEGACY_NO_CREDIT_LEDGER_TYPES,
  NO_CREDIT_LEDGER_TYPE,
  OWN_BALANCE_LEDGER_TYPE,
  SEX_ELIGIBILITY_TYPES,
  SYSTEM_LEAVE_TYPE_NAMES,
  normalizeEligibleEmploymentTypes,
  normalizeEmployeeDetailSchema,
  normalizeEntitlementBasis,
}) {
  function systemLeaveTypeDisplayName(name) {
    const labels = {
      vacationLeave: 'Vacation Leave',
      mandatoryForcedLeave: 'Mandatory/Forced Leave',
      sickLeave: 'Sick Leave',
      maternityLeave: 'Maternity Leave',
      paternityLeave: 'Paternity Leave',
      specialPrivilegeLeave: 'Special Privilege Leave',
      soloParentLeave: 'Solo Parent Leave',
      studyLeave: 'Study Leave',
      tenDayVawcLeave: '10-Day VAWC Leave',
      rehabilitationPrivilege: 'Rehabilitation Privilege',
      specialLeaveBenefitsForWomen: 'Special Leave Benefits for Women',
      specialEmergencyCalamityLeave: 'Special Emergency (Calamity) Leave',
      adoptionLeave: 'Adoption Leave',
      others: 'Others',
    };
    return labels[name] || name;
  }

  function slugLeaveTypeName(displayName) {
    const source = (displayName || '').toString().trim();
    const words = source.match(/[A-Za-z0-9]+/g) || [];
    if (words.length === 0) return null;
    const [first, ...rest] = words;
    const base = [
      first.toLowerCase(),
      ...rest.map((w) => `${w[0].toUpperCase()}${w.slice(1).toLowerCase()}`),
    ].join('');
    return base.endsWith('Leave') ? base : `${base}Leave`;
  }

  function leaveTypeRuleDefaults(name) {
    return (
      LEAVE_TYPE_RULES[name] || {
        employee_can_file: true,
        admin_only: false,
        allows_past_dates: true,
        requires_attachment: true,
        requires_attachment_when_over_days: null,
        max_days: null,
        minimum_advance_days: null,
        affects_dtr_normally: true,
        sex_eligibility: defaultSexEligibilityForLeaveType(name),
      }
    );
  }

  function defaultSexEligibilityForLeaveType(leaveTypeName) {
    if (
      leaveTypeName === 'maternityLeave' ||
      leaveTypeName === 'tenDayVawcLeave' ||
      leaveTypeName === 'specialLeaveBenefitsForWomen'
    ) {
      return 'female';
    }
    if (leaveTypeName === 'paternityLeave') return 'male';
    return 'any';
  }

  function normalizeSexEligibility(value, leaveTypeName) {
    const raw = (value || '').toString().trim().toLowerCase();
    if (raw === 'female_only' || raw === 'femaleonly') return 'female';
    if (raw === 'male_only' || raw === 'maleonly') return 'male';
    if (raw === 'both' || raw === 'all' || raw === 'bothsexes') return 'any';
    if (SEX_ELIGIBILITY_TYPES.has(raw)) return raw;
    return defaultSexEligibilityForLeaveType(leaveTypeName);
  }

  function defaultLedgerTypeForLeaveType(leaveTypeName) {
    if (leaveTypeName === 'mandatoryForcedLeave') return 'vacationLeave';
    if (leaveTypeName === 'vacationLeave' || leaveTypeName === 'sickLeave') {
      return leaveTypeName;
    }
    return NO_CREDIT_LEDGER_TYPE;
  }

  function normalizeLedgerType(value, leaveTypeName) {
    const raw = (value || '').toString().trim();
    if (raw === 'mandatoryForcedLeave') return 'vacationLeave';
    if (BALANCE_LEDGER_CONFIG_TYPES.has(raw)) return raw;
    if (CREDIT_BALANCE_BUCKET_TYPES.has(raw)) return raw;
    if (LEGACY_NO_CREDIT_LEDGER_TYPES.has(raw)) return NO_CREDIT_LEDGER_TYPE;
    if (raw && raw === leaveTypeName && !SYSTEM_LEAVE_TYPE_NAMES.includes(leaveTypeName)) {
      return OWN_BALANCE_LEDGER_TYPE;
    }
    return defaultLedgerTypeForLeaveType(leaveTypeName);
  }

  function creditBalanceLabel(ledgerType, leaveTypeName) {
    if (ledgerType === 'vacationLeave') return 'Vacation Leave';
    if (ledgerType === 'sickLeave') return 'Sick Leave';
    return systemLeaveTypeDisplayName(leaveTypeName || ledgerType || 'leave');
  }

  function leaveTypePayloadFromBody(body = {}, existing = null) {
    const displayName = (body.display_name ?? body.displayName ?? body.description ?? '')
      .toString()
      .trim();
    const rawName = (body.name ?? '').toString().trim();
    const name = rawName || slugLeaveTypeName(displayName);
    const base = leaveTypeRuleDefaults(name);

    function camelKey(key) {
      return key.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
    }

    function bodyField(key) {
      const camel = camelKey(key);
      if (Object.prototype.hasOwnProperty.call(body, key)) return body[key];
      if (Object.prototype.hasOwnProperty.call(body, camel)) return body[camel];
      return undefined;
    }

    function boolField(key, fallback) {
      const value = bodyField(key);
      if (value === undefined || value == null) return fallback;
      if (typeof value === 'boolean') return value;
      return ['true', '1', 'yes', 'y'].includes(String(value).trim().toLowerCase());
    }

    function invalidNumericField(label, requirement) {
      const err = new Error(`${label} ${requirement}.`);
      err.statusCode = 400;
      throw err;
    }

    function numberField(
      key,
      fallback = null,
      { label = key, minimum = null, exclusiveMinimum = false } = {},
    ) {
      const value = bodyField(key);
      if (value === undefined) return fallback;
      if (value == null || value === '') return null;
      const text = String(value).trim();
      if (!/^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(text)) {
        invalidNumericField(label, 'must be a valid number');
      }
      const n = Number(text);
      if (!Number.isFinite(n)) invalidNumericField(label, 'must be a valid number');
      if (minimum != null) {
        const invalid = exclusiveMinimum ? n <= minimum : n < minimum;
        if (invalid) {
          invalidNumericField(
            label,
            exclusiveMinimum ? `must be greater than ${minimum}` : `must be at least ${minimum}`,
          );
        }
      }
      return n;
    }

    function integerField(key, fallback = null, { label = key, minimum = 0 } = {}) {
      const value = bodyField(key);
      if (value === undefined) return fallback;
      if (value == null || value === '') return null;
      const text = String(value).trim();
      if (!/^\d+$/.test(text)) {
        invalidNumericField(label, 'must be a whole number');
      }
      const n = Number(text);
      if (!Number.isSafeInteger(n) || n < minimum) {
        invalidNumericField(label, `must be a whole number of ${minimum} or more`);
      }
      return n;
    }

    const payload = {
      id: existing?.id || null,
      name,
      displayName:
        displayName ||
        existing?.display_name ||
        existing?.description ||
        systemLeaveTypeDisplayName(name),
      description:
        (body.description ?? existing?.description ?? displayName ?? '').toString().trim() || null,
      isActive: boolField('is_active', existing?.is_active ?? true),
      employeeCanFile: boolField(
        'employee_can_file',
        existing?.employee_can_file ?? base.employee_can_file !== false,
      ),
      adminOnly: boolField('admin_only', existing?.admin_only ?? base.admin_only === true),
      adminCanFile: boolField('admin_can_file', existing?.admin_can_file ?? true),
      allowsPastDates: boolField(
        'allows_past_dates',
        existing?.allows_past_dates ?? base.allows_past_dates !== false,
      ),
      requiresAttachment: boolField(
        'requires_attachment',
        existing?.requires_attachment ?? base.requires_attachment === true,
      ),
      requiresAttachmentWhenOverDays: numberField(
        'requires_attachment_when_over_days',
        existing?.requires_attachment_when_over_days ??
          base.requires_attachment_when_over_days ??
          null,
        {
          label: 'Attachment threshold days',
          minimum: 0,
          exclusiveMinimum: true,
        },
      ),
      maxDays: numberField('max_days', existing?.max_days ?? base.max_days ?? null, {
        label: 'Maximum working days',
        minimum: 0,
        exclusiveMinimum: true,
      }),
      minimumAdvanceDays: integerField(
        'minimum_advance_days',
        existing?.minimum_advance_days ?? base.minimum_advance_days ?? null,
        { label: 'Minimum advance days', minimum: 0 },
      ),
      firstYearAllowance:
        bodyField('first_year_allowance') ?? existing?.first_year_allowance ?? 'full',
      minimumServiceMonths:
        integerField('minimum_service_months', existing?.minimum_service_months ?? 0, {
          label: 'Minimum months of service',
          minimum: 0,
        }) ?? 0,
      affectsDtrNormally: boolField(
        'affects_dtr_normally',
        existing?.affects_dtr_normally ?? base.affects_dtr_normally !== false,
      ),
      balanceLedgerType: normalizeLedgerType(
        body.balance_ledger_type ?? body.balanceLedgerType ?? existing?.balance_ledger_type,
        name,
      ),
      entitlementBasis: normalizeEntitlementBasis(
        body.entitlement_basis ?? body.entitlementBasis ?? existing?.entitlement_basis,
        name,
      ),
      sexEligibility: normalizeSexEligibility(
        body.sex_eligibility ??
          body.sexEligibility ??
          existing?.sex_eligibility ??
          base.sex_eligibility,
        name,
      ),
      eligibleEmploymentTypes: normalizeEligibleEmploymentTypes(
        Object.prototype.hasOwnProperty.call(body, 'eligible_employment_types')
          ? body.eligible_employment_types
          : (existing?.eligible_employment_types ?? null),
      ),
      employeeDetailSchema: normalizeEmployeeDetailSchema(
        bodyField('employee_detail_schema') ?? existing?.employee_detail_schema ?? [],
        { strict: true },
      ),
    };
    if (payload.minimumServiceMonths > 1200)
      invalidNumericField('Minimum months of service', 'must be 1200 or less');
    if (!['full', 'prorated'].includes(payload.firstYearAllowance))
      invalidNumericField('First-year allowance', 'must be full or prorated');
    if (
      payload.firstYearAllowance === 'prorated' &&
      (payload.entitlementBasis !== 'annual' ||
        !payload.maxDays ||
        payload.balanceLedgerType !== 'none')
    ) {
      throw Object.assign(
        new Error(
          'First-year proration requires an annual entitlement with a positive maximum and no credit ledger.',
        ),
        { statusCode: 400 },
      );
    }
    return payload;
  }
  return {
    systemLeaveTypeDisplayName,
    slugLeaveTypeName,
    leaveTypeRuleDefaults,
    defaultSexEligibilityForLeaveType,
    normalizeSexEligibility,
    defaultLedgerTypeForLeaveType,
    normalizeLedgerType,
    creditBalanceLabel,
    leaveTypePayloadFromBody,
  };
};
