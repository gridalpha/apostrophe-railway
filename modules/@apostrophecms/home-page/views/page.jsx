// The home page.
//
// Changed from the stock starter kit in two ways, both for a hosted deploy:
// the welcome block appears only while the `main` area is still empty, so the
// first thing an editor adds becomes the real home page; and the sign-in copy
// describes the Railway variables that created the administrator rather than a
// CLI command nobody can run against a container.

export default function ({ page, user, query }, { Extend, Area }) {
  const empty = !(page.main && page.main.items && page.main.items.length);
  return (
    <Extend
      templateName="layout.jsx"
      main={
        <section className="bp-welcome">
          {empty && (
            <>
              <h1 className="bp-welcome__headline">
                Welcome to ApostropheCMS
              </h1>
              {!user && (
                <>
                  <h3 className="bp-welcome__help">This site has no content yet</h3>
                  <p>
                    Sign in with the <code>ADMIN_USERNAME</code> and <code>ADMIN_PASSWORD</code> set
                    on this service in Railway, switch the admin bar to <span className="bp-mode">Edit</span>{' '}
                    mode, and this block is replaced by whatever you put on the page.
                  </p>
                  <p className="bp-welcome__cta">
                    <a className="bp-button bp-button--cta" href="/login">Log in</a>
                  </p>
                </>
              )}
              <p>
                For a guide on how to configure and customize this project, <a href="https://apostrophecms.com/docs">please check out the Apostrophe documentation</a>.
              </p>
            </>
          )}
          <div className="bp-welcome__area">
            {user && empty && (query['apos-edit'] ? (
              <p>
                Add and edit content below in the content area. 👇
              </p>
            ) : (
              <p>
                Enter <span className="bp-mode">Edit</span> mode from the admin bar <span style="display:inline-block; transform: rotate(45deg)">👆</span> to begin.
              </p>
            ))}
            <Area doc={page} name="main" />
          </div>
        </section>
      }
    />
  );
}
