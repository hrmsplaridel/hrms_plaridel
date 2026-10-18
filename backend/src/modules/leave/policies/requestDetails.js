'use strict';
module.exports = function createLeaveComponent({}) {
  function readMaternityDeliveryType(details) {
    if (!details || typeof details !== 'object') return null;
    return (
      details.maternity_delivery_type ||
      details.maternityDeliveryType ||
      details.maternity_delivery ||
      details.delivery_type ||
      null
    );
  }

  function readAdoptionParentRole(details) {
    if (!details || typeof details !== 'object') return null;
    return (
      details.adoption_parent_role ||
      details.adoptionParentRole ||
      details.adoptive_parent_role ||
      details.adoptiveParentRole ||
      null
    );
  }

  function readFirstDetailValue(details, keys) {
    if (!details || typeof details !== 'object') return null;
    for (const key of keys) {
      const value = details[key];
      if (value != null && `${value}`.trim() !== '') return value;
    }
    return null;
  }

  function readLeaveEventDates(details) {
    return {
      expectedDeliveryDate: readFirstDetailValue(details, [
        'expected_delivery_date',
        'expectedDeliveryDate',
        'maternity_expected_delivery_date',
        'maternityExpectedDeliveryDate',
      ]),
      childDeliveryDate: readFirstDetailValue(details, [
        'child_delivery_date',
        'childDeliveryDate',
        'delivery_date',
        'deliveryDate',
        'spouse_delivery_date',
        'spouseDeliveryDate',
      ]),
      accidentDate: readFirstDetailValue(details, ['accident_date', 'accidentDate']),
      calamityDate: readFirstDetailValue(details, [
        'calamity_date',
        'calamityDate',
        'calamity_occurrence_date',
        'calamityOccurrenceDate',
      ]),
      adoptionPlacementDate: readFirstDetailValue(details, [
        'adoption_placement_date',
        'adoptionPlacementDate',
        'adoption_finalization_date',
        'adoptionFinalizationDate',
        'papa_date',
        'papaDate',
      ]),
      soloParentIdExpiryDate: readFirstDetailValue(details, [
        'solo_parent_id_expiry_date',
        'soloParentIdExpiryDate',
        'solo_parent_id_valid_until',
        'soloParentIdValidUntil',
      ]),
    };
  }

  function parseJsonBodyField(value) {
    if (value == null || typeof value !== 'string') return value;
    const text = value.trim();
    if (!text) return value;
    try {
      return JSON.parse(text);
    } catch (_) {
      return value;
    }
  }
  return {
    readMaternityDeliveryType,
    readAdoptionParentRole,
    readFirstDetailValue,
    readLeaveEventDates,
    parseJsonBodyField,
  };
};
