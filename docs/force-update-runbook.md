# Force update — how to use it

Shipped in **1.5**. Governs 1.5 and later only (see the limitation at the bottom).

## One-time setup

The gate reads `config/appVersion`, which is outside every existing rule, so
Firestore denies it by default. Until this rule is deployed the gate simply never
fires — it fails open — so shipping 1.5 before adding it is safe.

Add to `firestore.rules`:

```
match /config/{document} {
  allow read: if true;      // must be readable before sign-in
  allow write: if false;    // console only
}
```

Read-only and contains no user data, so a public read is fine.

## Forcing an update

Firebase Console → Firestore → create `config/appVersion`:

| Field | Type | Example | Required |
|---|---|---|---|
| `minimumSupportedVersion` | string | `1.6` | yes |
| `updateMessage` | string | `Billing needs the latest version.` | no |
| `storeURL` | string | `itms-apps://apps.apple.com/app/id6763451242` | no |

Anyone on a build **below** `minimumSupportedVersion` gets a non-dismissible
wall. Set it to `1.6` and every 1.5 user is blocked until they update.

Leave `updateMessage` empty unless you need something specific — the built-in
string is translated into all 15 languages; yours will not be.

**To stop forcing:** delete the document, or set `minimumSupportedVersion` to a
version nobody is below (e.g. `0`). Takes effect on the next launch or foreground.

## Behaviour

- Checked at cold launch and on every foreground, so a build can be retired
  mid-session.
- Sits above the auth gate — an unsupported build cannot even sign in.
- No dismiss, no skip. That is the point.
- **Fails open.** Missing document, denied read, malformed value, or no network
  all resolve to "not blocked". A version gate that failed closed would turn any
  backend hiccup into a bricked app for every user simultaneously.
- Comparison is numeric per component, so `1.10` is correctly newer than `1.9`,
  and `1.5` equals `1.5.0`. Unparseable values never block.

## The limitation — builds ≤ 1.4 can never be forced

The check has to exist inside the installed binary. Builds shipped before 1.5
contain no gate, so no server configuration can reach them. There is no App Store
or iOS mechanism to force an already-installed app to update.

For users on 1.4 and below the only levers are:

- a push notification asking them to update (FCM is already wired),
- email to the address on their account,
- attrition — most iOS users have automatic updates enabled and will move on
  their own within days of a release.

Deliberately **not** recommended: breaking old clients server-side by tightening
Security Rules. It cannot show an explanatory message, so it presents as a crash
or an empty app, and Firestore rules cannot reliably see the client version.
