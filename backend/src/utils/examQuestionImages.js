/**
 * Helpers for exam question / choice images (recruitment_exam_questions).
 * Images are stored as files under uploads/exam-images; only the relative path is
 * kept in PostgreSQL.
 */
const EXAM_IMAGE_SUBDIR = 'exam-images';
const EXAM_IMAGE_MAX_BYTES = 8 * 1024 * 1024;
const EXAM_IMAGE_CAPTION_MAX = 300;

const EXAM_IMAGE_FILE_RE = /^[A-Za-z0-9-]{8,64}\.(png|jpe?g|webp)$/i;
const EXAM_IMAGE_PATH_RE = new RegExp(
  `^${EXAM_IMAGE_SUBDIR}/[A-Za-z0-9-]{8,64}\\.(png|jpe?g|webp)$`,
  'i',
);

/** Returns the trimmed relative path when it is a valid exam image path, else null. */
function sanitizeExamImagePath(value) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  return EXAM_IMAGE_PATH_RE.test(v) ? v : null;
}

function sanitizeExamImageCaption(value) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  if (!v) return null;
  return v.length > EXAM_IMAGE_CAPTION_MAX ? v.slice(0, EXAM_IMAGE_CAPTION_MAX) : v;
}

/**
 * Per-choice image paths, always the same length as the options list.
 * Returns null when no choice has an image so text-only rows stay unchanged.
 */
function normalizeOptionImages(optionImages, optionCount) {
  if (!Array.isArray(optionImages) || optionCount <= 0) return null;
  const out = [];
  let any = false;
  for (let i = 0; i < optionCount; i += 1) {
    const p = sanitizeExamImagePath(optionImages[i]);
    if (p) any = true;
    out.push(p);
  }
  return any ? out : null;
}

/** Every image path referenced by one stored row. */
function imagePathsFromRow(row) {
  const out = [];
  const q = sanitizeExamImagePath(row?.question_image_path);
  if (q) out.push(q);
  const opts = row?.option_images_json;
  if (Array.isArray(opts)) {
    for (const o of opts) {
      const p = sanitizeExamImagePath(o);
      if (p) out.push(p);
    }
  }
  return out;
}

module.exports = {
  EXAM_IMAGE_SUBDIR,
  EXAM_IMAGE_MAX_BYTES,
  EXAM_IMAGE_FILE_RE,
  sanitizeExamImagePath,
  sanitizeExamImageCaption,
  normalizeOptionImages,
  imagePathsFromRow,
};
