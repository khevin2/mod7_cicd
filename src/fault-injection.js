function createFaultInjection() {
  let enabled = false;

  return {
    enable() {
      enabled = true;
    },
    disable() {
      enabled = false;
    },
    isEnabled() {
      return enabled;
    }
  };
}

module.exports = { createFaultInjection };
