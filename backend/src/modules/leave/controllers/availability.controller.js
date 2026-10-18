'use strict';
module.exports = function createLeaveControllers({ pool, resolveFinalLeaveReviewers }) {
  return {
    getFinalReviewerEligibility: async (req, res) => {
      try {
        const reviewers =
          req.user.role === 'mayor'
            ? (
                await pool.query(
                  "SELECT id FROM users WHERE id=$1 AND role='mayor' AND is_active=true",
                  [req.user.id],
                )
              ).rows
            : await resolveFinalLeaveReviewers(pool);
        return res.json({
          can_review: reviewers.some((reviewer) => String(reviewer.id) === String(req.user.id)),
        });
      } catch (err) {
        console.error('[leave GET final-reviewer/me]', err);
        return res.status(500).json({ error: 'Failed to check final leave reviewer assignment' });
      }
    },

    getSubmissionAvailability: async (req, res) => {
      try {
        res.json(
          await require('../../../services/leaveSubmissionAvailability').getLeaveSubmissionAvailability(
            pool,
            req.user.id,
          ),
        );
      } catch (err) {
        console.error('[leave GET submission-availability]', err);
        res.status(500).json({ error: 'Failed to check leave reviewer availability' });
      }
    },
  };
};
