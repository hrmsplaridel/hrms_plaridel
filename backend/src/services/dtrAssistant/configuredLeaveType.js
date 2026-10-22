function words(value) {
  return String(value || '').replace(/([a-z])([A-Z])/g, '$1 $2')
    .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

// Match configured names, never incidental words in a policy description.
function configuredLeaveType(text, types = []) {
  const message = ` ${words(text)} `;
  const matches = [];
  for (const type of types) {
    if (type.is_active === false) continue;
    const aliases = [type.name, type.display_name, type.code, type.leave_type]
      .map(words).filter((name) => name && name !== 'leave');
    const score = Math.max(0, ...aliases.map((name) => message.includes(` ${name} `) ? name.length : 0));
    if (score) matches.push({ type, score });
  }
  matches.sort((a, b) => b.score - a.score);
  if (!matches.length || (matches[1] && matches[0].score === matches[1].score)) return null;
  return matches[0].type;
}

module.exports = { configuredLeaveType };
