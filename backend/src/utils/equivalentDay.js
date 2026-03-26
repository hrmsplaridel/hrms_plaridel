function _round3(x) {
  return Math.round((x + Number.EPSILON) * 1000) / 1000;
}

/**
 * Compute equivalent day deduction from minutes.
 * equivalent_day = round(minutes / (work_hours_per_day * 60), 3)
 * If multiplier != 1.0, adjusted = round(equivalent_day * multiplier, 3)
 */
function computeEquivalentDay({
  minutes,
  workHoursPerDay = 8,
  useEquivalentDayConversion = true,
  deductionMultiplier = 1.0,
}) {
  const mins = Math.max(0, parseInt(minutes ?? 0, 10) || 0);
  const wh = parseFloat(workHoursPerDay);
  const mult = parseFloat(deductionMultiplier);

  if (!useEquivalentDayConversion) {
    return {
      equivalent_day: 0,
      adjusted_equivalent_day: 0,
      base_minutes: mins,
      work_hours_per_day: wh,
      deduction_multiplier: mult,
      used_conversion: false,
    };
  }

  const denom = wh > 0 ? wh * 60 : 480;
  const eq = _round3(mins / denom);
  const adj = _round3(eq * (mult > 0 ? mult : 1.0));
  return {
    equivalent_day: eq,
    adjusted_equivalent_day: adj,
    base_minutes: mins,
    work_hours_per_day: wh,
    deduction_multiplier: mult,
    used_conversion: true,
  };
}

module.exports = { computeEquivalentDay };

