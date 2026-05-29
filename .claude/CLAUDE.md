# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A teaching demo (for a security class) of three-legged OAuth 2.0 + OpenID Connect
"Sign in with Google", built as a single-file Roda web app (`app.rb`). It is
deliberately a one-process monolith that plays BOTH halves of the flow — the
"client" that talks to Google AND the "resource server" that trusts the result —
so students see the whole OIDC workflow in one file. Clarity for students trumps
production patterns; favor readable, heavily-commented code over abstraction.

## Commands

- Run the app: `rake run` (or `bundle exec puma -p 4567`) — serves on http://localhost:4567
- Install deps: `bundle` (Ruby version pinned in `.ruby-version`; use `rbenv install $(cat .ruby-version)`)
- Lint: `bundle exec rubocop` (config in `.rubocop.yml`, targets Ruby 3.2)

There is no test suite.

## Setup required to run

The app will not function without secrets. Copy `config/secrets.example.yml` to
`config/secrets.yml` (gitignored) and fill in `GOOGLE_CLIENT_ID` /
`GOOGLE_CLIENT_SECRET` from a Google Cloud Console OAuth 2.0 Client ID (type: Web
application). That client MUST register the redirect URI
`http://localhost:4567/google_callback` byte-for-byte, matching `REDIRECT_URI` in
`app.rb`. Secrets are loaded into `ENV` via Figaro and read through
`OAuthDemo.config` / the instance `config` helper.

## Architecture / flow

The entire app is `app.rb`. The authorization-code flow spans four routes:

- `GET /login` — generates a random `state` (anti-CSRF nonce) stored in the
  session, then links the user to Google's auth URL.
- `GET /google_callback` — verifies `state` matches, exchanges the one-time
  `code` for tokens server-side (this call carries `client_secret`, never the
  browser), then verifies the returned `id_token` and stores identity claims in
  the session.
- `GET /secret` — gated content; redirects to `/login` unless `session[:auth_info]` exists.
- `GET /logout` — clears the session identity.

The pedagogical heart is `verify_google_id_token` + `google_signing_key`. This is
the OIDC distinction the demo exists to show: instead of spending an opaque
access token on a userinfo endpoint, identity comes from a signed JWT (`id_token`).
Verification (1) reads the unverified header to find the signing `kid`, (2) fetches
Google's JWKS public keys, (3) verifies the RS256 signature, and (4) validates
`iss`/`aud`/`exp` manually — `aud` MUST equal our own client id, which is what
prevents a token minted for another app from being replayed here.

Google endpoint URLs, issuers, scope, and `REDIRECT_URI` are constants near the
top of the class; they derive from Google's discovery document
(https://accounts.google.com/.well-known/openid-configuration).

## Notes

- The `puts` calls in `/google_callback` (raw JWT, verified claims) are intentional
  teaching aids that print to the server console — don't remove them as "debug noise".
- Git history shows this demo was migrated from plain GitHub OAuth 2.0 to Google
  OAuth 2.0 + OIDC; the OIDC identity-via-signed-token step is the point of the change.
