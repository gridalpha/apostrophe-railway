export default {
  options: {
    // Railway terminates TLS at its edge and reaches the container over plain
    // HTTP from 100.64.0.0/10, overwriting any client-supplied
    // X-Forwarded-For, so trusting every hop lands Express on the leftmost
    // entry — the real client — and makes req.secure follow
    // X-Forwarded-Proto. Without it the session cookie below can never be set.
    trustProxy: true,
    session: {
      // Apostrophe reads APOS_SESSION_SECRET over this value; the entrypoint
      // guarantees one is present, so leaving it undefined here is correct.
      secret: undefined,
      cookie: {
        // The health prober speaks plain HTTP and starts no session, so this
        // costs nothing there. Set APOS_COOKIE_SECURE=0 only if you serve the
        // site over plain HTTP on purpose.
        secure: process.env.APOS_COOKIE_SECURE !== '0'
      }
    }
  }
};
