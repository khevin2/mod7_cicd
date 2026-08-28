function createLogger(output = console, clock = () => new Date().toISOString()) {
  function write(level, event, fields = {}) {
    // Callers supply only an explicit allowlist of operational fields. Do not
    // pass request headers, cookies, bodies, query strings, user identifiers,
    // error messages, or arbitrary error objects to this logger.
    output.log(
      JSON.stringify({
        timestamp: clock(),
        level,
        event,
        ...fields
      })
    );
  }

  return {
    info: (event, fields) => write('info', event, fields),
    error: (event, fields) => write('error', event, fields)
  };
}

module.exports = { createLogger };
