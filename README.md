# OAuth 2.0 + OpenID Connect Demo (Sign in with Google)

A small teaching demo of three-legged **OAuth 2.0 + OpenID Connect (OIDC)**
"Sign in with Google", built as a single-file [Roda](https://roda.jeremyevans.net/)
web app (`app.rb`).

It is deliberately a one-process monolith that plays **both** halves of the flow —
the *client* that talks to Google **and** the *resource server* that trusts the
result — so the whole OIDC workflow is visible in one file.

## What it demonstrates

Plain OAuth 2.0 answers *"can this app act on the user's behalf?"* and hands back
an opaque access token that you then spend on a userinfo endpoint to learn who the
user is. **OpenID Connect adds an identity layer**: the token response also carries
a signed `id_token` (a JWT) whose claims already say who the user is.

The heart of the demo is `verify_google_id_token` in `app.rb`, which establishes
identity by **cryptography** rather than by trusting a callback:

1. Read the token header (unverified) to find which key (`kid`) signed it.
2. Fetch Google's public keys (JWKS).
3. Verify the RS256 signature with the matching key.
4. Validate the `iss` / `aud` / `exp` claims manually — `aud` must equal our own
   client id, which is what stops a token minted for another app from being
   replayed against us.

## Prerequisites

- **Ruby** — the version pinned in [`.ruby-version`](.ruby-version)
  (install with e.g. `rbenv install $(cat .ruby-version)`).
- **Bundler** (`gem install bundler`).
- A **Google account** to create OAuth credentials.

## Setup

### 1. Install dependencies

```bash
bundle
```

### 2. Create a Google OAuth 2.0 Client ID

In the [Google Cloud Console](https://console.cloud.google.com/) →
**APIs & Services → Credentials**:

1. Create an **OAuth 2.0 Client ID** of type **Web application**.
2. Add this **Authorized redirect URI**, exactly (byte-for-byte):

   ```
   http://localhost:4567/google_callback
   ```

   This must match `REDIRECT_URI` in `app.rb`.
3. Note the generated **Client ID** and **Client secret**.

### 3. Add your secrets

Copy the example file and fill in your credentials:

```bash
cp config/secrets.example.yml config/secrets.yml
```

Then edit `config/secrets.yml`:

```yaml
development:
  GOOGLE_CLIENT_ID: <your Google OAuth client id>
  GOOGLE_CLIENT_SECRET: <your Google OAuth client secret>
  SESSION_SECRET: <a long random string>
```

`config/secrets.yml` is gitignored — it is never committed. Generate a fresh
`SESSION_SECRET` with `bundle exec ruby -rsecurerandom -e 'puts SecureRandom.base64(64)'`.

## Running

```bash
rake run
```

(equivalently: `bundle exec puma -p 4567`)

Then open <http://localhost:4567> and follow the **secret to life** link to start
the sign-in flow. The server console prints the raw `id_token` JWT and the verified
claims as you go — these are intentional teaching aids.

## Routes

| Route                   | Purpose                                                                 |
| ----------------------- | ----------------------------------------------------------------------- |
| `GET /`                 | Landing page linking to the gated content.                              |
| `GET /secret`           | Gated content; redirects to `/login` unless signed in.                  |
| `GET /login`            | Step 1: generate anti-CSRF `state`, link to Google's auth URL.          |
| `GET /google_callback`  | Step 2: verify `state`, exchange `code` for tokens, verify `id_token`.  |
| `GET /logout`           | Clear the session identity.                                             |

## Linting

```bash
bundle exec rubocop
```
