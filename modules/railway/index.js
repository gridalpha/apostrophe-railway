// Deployment glue for Railway. Two jobs, both of which have to happen outside
// the browser: a health route the platform's anonymous prober can reach, and a
// first administrator created before anything listens.
//
// Nothing here is Apostrophe-specific advice — delete this module if you move
// the project somewhere else.

export default {
  middleware(self) {
    return {
      // Railway's health prober is anonymous and sends no X-Forwarded-Proto,
      // so it cannot use any editor route. This one reads a document, which
      // makes it a real check on the database rather than on the container:
      // a deployment whose MongoDB is unreachable never goes healthy.
      //
      // The path has no dot or hyphen, which Railway's healthcheckPath rejects.
      async healthz(req, res, next) {
        if (req.path !== '/healthz') {
          return next();
        }
        try {
          await self.apos.doc.db.findOne({}, { projection: { _id: 1 } });
          return res.status(200).send('ok');
        } catch (e) {
          self.apos.util.error('[railway] health check failed', e);
          return res.status(503).send('database unavailable');
        }
      }
    };
  },
  tasks(self) {
    return {
      'create-admin': {
        usage: 'Usage: node app railway:create-admin\n\nCreates the first administrator from ADMIN_USERNAME and ADMIN_PASSWORD if that account does not exist yet. Idempotent: an existing account is never modified, so a password changed in the admin UI is not reverted by a redeploy.',
        async task() {
          const username = (process.env.ADMIN_USERNAME || 'admin').trim();
          const password = process.env.ADMIN_PASSWORD;
          const req = self.apos.task.getReq();

          const existing = await self.apos.user
            .find(req, { username: self.apos.login.normalizeLoginName(username) })
            .toObject();
          if (existing) {
            self.apos.util.log(`[railway] user "${username}" already exists, leaving it alone`);
            return;
          }
          if (!password) {
            throw new Error(
              '[railway] ADMIN_PASSWORD is not set, so the first administrator cannot be created. Set it and redeploy.'
            );
          }
          if (password.length < 8) {
            throw new Error('[railway] ADMIN_PASSWORD must be at least 8 characters.');
          }
          await self.apos.user.insert(req, {
            username,
            title: username,
            role: 'admin',
            password
          });
          self.apos.util.log(`[railway] created administrator "${username}"`);
        }
      }
    };
  }
};
