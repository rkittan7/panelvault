/** Collect and parse a JSON request body with a size gate and an inactivity
 * timeout. The timer is refreshed for every chunk so a slow but healthy upload
 * is not mistaken for a stalled connection. */
function readJSONBody(req, { limit = 1_000_000, idleTimeout = 10_000 } = {}) {
  if (req.panelVaultBodyPromise) return req.panelVaultBodyPromise;
  req.panelVaultBodyPromise = new Promise((resolve, reject) => {
    let raw = "";
    let settled = false;
    let timer = null;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      req.off("data", onData);
      req.off("end", onEnd);
      req.off("error", onError);
      callback(value);
    };
    const armIdleTimer = () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        req.resume();
        finish(reject, new Error("request body timed out"));
      }, idleTimeout);
    };
    const onData = (chunk) => {
      armIdleTimer();
      raw += chunk;
      if (raw.length > limit) {
        req.resume();
        finish(reject, new Error("body too large"));
      }
    };
    const onEnd = () => {
      try {
        finish(resolve, raw ? JSON.parse(raw) : {});
      } catch {
        finish(reject, new Error("invalid json"));
      }
    };
    const onError = (error) => finish(reject, error);
    armIdleTimer();
    req.on("data", onData);
    req.on("end", onEnd);
    req.on("error", onError);
  });
  return req.panelVaultBodyPromise;
}

module.exports = { readJSONBody };
