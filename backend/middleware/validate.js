// Reusable, dependency-free input validators used across all API routes.
//
// Validation here is a SECURITY boundary, not a UX nicety: the mobile app is
// treated as untrusted. Every externally controlled value is checked for type,
// length, and format before it reaches Supabase.
//
// All validators are pure functions returning booleans so they can be unit
// tested without a server.

const EMAIL_RULE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RULE = /^[0-9+\-\s()]{6,20}$/;
const UUID_RULE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_DATE_RULE = /^\d{4}-\d{2}-\d{2}$/;

const BLOOD_GROUPS = new Set([
  'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown',
]);

function isString(value) {
  return typeof value === 'string';
}

function isNonEmptyString(value) {
  return isString(value) && value.trim().length > 0;
}

function hasMaxLength(value, max) {
  return isString(value) && value.length <= max;
}

function isOptionalField(value) {
  return value === undefined || value === null;
}

// RFC-ish email shape, length capped at the practical 254-character limit.
function isValidEmail(value) {
  return (
    isNonEmptyString(value) &&
    value.length <= 254 &&
    EMAIL_RULE.test(value)
  );
}

// Optional email: must be valid when present.
function isValidOptionalEmail(value) {
  return isOptionalField(value) || isValidEmail(value);
}

// Phone numbers are contact data for SMS/call intents only — no strict
// international format is enforced, just a safe character set + sane length.
function isValidPhone(value) {
  return (
    isNonEmptyString(value) &&
    value.length <= 30 &&
    PHONE_RULE.test(value.trim())
  );
}

function isValidOptionalPhone(value) {
  return isOptionalField(value) || isValidPhone(value);
}

function isValidUuid(value) {
  return isNonEmptyString(value) && UUID_RULE.test(value);
}

function isValidHttpUrl(value) {
  if (!isString(value) || value.length > 2048) return false;
  let parsed;
  try {
    parsed = new URL(value);
  } catch (_) {
    return false;
  }
  return parsed.protocol === 'https:' || parsed.protocol === 'http:';
}

function isValidIsoDate(value) {
  if (!isNonEmptyString(value) || value.length > 10 || !ISO_DATE_RULE.test(value)) {
    return false;
  }
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function isValidBloodGroup(value) {
  return isString(value) && BLOOD_GROUPS.has(value);
}

module.exports = {
  BLOOD_GROUPS,
  isValidEmail,
  isValidOptionalEmail,
  isValidPhone,
  isValidOptionalPhone,
  isValidUuid,
  isValidHttpUrl,
  isValidIsoDate,
  isValidBloodGroup,
  isNonEmptyString,
  hasMaxLength,
  isOptionalField,
};