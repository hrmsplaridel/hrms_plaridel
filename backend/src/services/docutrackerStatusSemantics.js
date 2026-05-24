const ACTIVE_WORKFLOW_STATUSES_FOR_OVERDUE = Object.freeze([
  'pending',
  'in_review',
  'returned',
  'escalated',
  'overdue',
]);

const ESCALATION_ELIGIBLE_WORKFLOW_STATUSES = Object.freeze(
  ACTIVE_WORKFLOW_STATUSES_FOR_OVERDUE.filter((s) => s !== 'overdue')
);

module.exports = {
  ACTIVE_WORKFLOW_STATUSES_FOR_OVERDUE,
  ESCALATION_ELIGIBLE_WORKFLOW_STATUSES,
};
