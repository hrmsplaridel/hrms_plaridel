function words(value) {
  return String(value || '').replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function configuredLocatorTypes(text, types = []) {
  const message = ` ${words(text)} `;
  return types.filter((type) => type.is_active !== false).map((type) => {
    const aliases = [type.code, type.label, type.short_label, type.request_type_label,
      String(type.label || '').replace(/^locator\s*[/:-]\s*/i, '')];
    const score = Math.max(0, ...aliases.map((value) => {
      const alias = words(value);
      if (!alias || alias === 'locator') return 0;
      if (alias.length < 3 && !new RegExp(`\\b${String(value).toUpperCase()}\\b`).test(String(text))) return 0;
      return message.includes(` ${alias} `) ? alias.length : 0;
    }));
    return { type, score };
  }).filter((match) => match.score).sort((a, b) => b.score - a.score).map((match) => match.type);
}

function configuredLocatorType(text, types) {
  return configuredLocatorTypes(text, types)[0] || null;
}

module.exports = { configuredLocatorType, configuredLocatorTypes };
