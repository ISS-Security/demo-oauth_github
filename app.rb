# frozen_string_literal: true

# Roda web app demonstrating Google "Sign in" via OAuth 2.0 + OpenID Connect.
#
# This is a single-process monolith on purpose: it plays BOTH halves of the
# flow (the "client" that talks to Google AND the "resource server" that
# trusts the result) so students can see the whole OIDC workflow in one file,
# without the App<->API delegation that the Tyto demo splits across two repos.
#
# Plain OAuth 2.0 (what the old GitHub version of this demo did) answers
# "can this app act on the user's behalf?" and hands back an opaque
# access_token, which you then spend on a userinfo endpoint to learn who the
# user is. OpenID Connect (OIDC) adds an identity layer: the token response
# ALSO carries a signed `id_token` (a JWT) whose claims already say who the
# user is. We verify that token's signature against Google's public keys
# (JWKS, RS256) and check its `iss`/`aud`/`exp` ourselves -- no userinfo hop,
# and the identity is established by cryptography rather than by trusting a
# callback. That verification step is the heart of this demo.
#
# Install:
# - clone this repo
# - rbenv install $(cat .ruby-version)
# - bundle
# - create a Google OAuth 2.0 Client ID (type: Web application) in the
#   Google Cloud Console, with authorized redirect URI:
#       http://localhost:4567/google_callback
# - put the client id/secret in config/secrets.yml (see secrets.example.yml)
#
# Run using:
#   rake run
# or:
#   bundle exec puma -p 4567

require 'rack/session'
require 'roda'
require 'figaro'
require 'http'
require 'json'
require 'jwt'
require 'securerandom'
require 'uri'

# Demo app for three-legged OAuth + OpenID Connect (Google)
class OAuthDemo < Roda
  plugin :environments

  configure do
    # load config secrets into local environment variables (ENV)
    Figaro.application = Figaro::Application.new(
      environment: environment,
      path: File.expand_path('config/secrets.yml')
    )
    Figaro.load
    def self.config = Figaro.env
  end

  ONE_MONTH = 30 * 24 * 60 * 60 # in seconds

  # --- Google OIDC endpoints (from Google's discovery document) -------------
  # https://accounts.google.com/.well-known/openid-configuration
  GOOGLE_AUTH_URL  = 'https://accounts.google.com/o/oauth2/v2/auth'
  GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
  GOOGLE_JWKS_URL  = 'https://www.googleapis.com/oauth2/v3/certs'
  # Google has historically issued the `iss` claim in both forms.
  GOOGLE_ISSUERS   = ['https://accounts.google.com', 'accounts.google.com'].freeze
  GOOGLE_SCOPE     = 'openid email profile'
  # Must match a redirect URI registered on the OAuth client byte-for-byte.
  REDIRECT_URI     = 'http://localhost:4567/google_callback'

  use Rack::Session::Cookie,
      expire_after: ONE_MONTH,
      secret: config.SESSION_SECRET

  def config
    @config ||= OAuthDemo.config
  end

  route do |routing|
    routing.root do
      'Tell me the <a href="/secret">secret to life</a>'
    end

    routing.get 'secret' do
      routing.redirect '/login' unless session[:auth_info]

      account = JSON.parse(session[:auth_info])
      name = account['name']
      email = account['email']
      "THE SECRET TO LIFE: Both your best friend and worst enemy is #{name} at #{email}"\
      "<BR><a href='/logout'>logout</a>"
    end

    # Step 1 of the authorization-code flow: send the user to Google.
    # `state` is a random anti-CSRF nonce we stash in the session now and
    # verify when Google redirects back -- it ties the callback to *this*
    # browser session so an attacker can't replay someone else's callback.
    routing.get 'login' do
      state = session[:oauth_state] = SecureRandom.hex(16)
      params = URI.encode_www_form(
        client_id: config.GOOGLE_CLIENT_ID,
        redirect_uri: REDIRECT_URI,
        response_type: 'code',
        scope: GOOGLE_SCOPE,
        state: state
      )
      "<a href='#{GOOGLE_AUTH_URL}?#{params}'>Login with Google</a>"
    end

    # Step 2: Google redirects back here with a one-time `code` (and our
    # `state`). We exchange the code for tokens server-side, then verify the
    # id_token cryptographically and read the identity claims from it.
    routing.get 'google_callback' do
      # Verify the CSRF state before doing anything else.
      expected_state = session.delete(:oauth_state)
      unless expected_state && routing.params['state'] == expected_state
        next 'OAuth state mismatch -- possible CSRF. <a href="/login">Try again</a>'
      end

      # Exchange the authorization code for tokens. This is a server-side
      # call that includes the client_secret, so it never touches the browser.
      token_response = HTTP.headers(accept: 'application/json')
                           .post(GOOGLE_TOKEN_URL,
                                 form: { client_id: config.GOOGLE_CLIENT_ID,
                                         client_secret: config.GOOGLE_CLIENT_SECRET,
                                         code: routing.params['code'],
                                         grant_type: 'authorization_code',
                                         redirect_uri: REDIRECT_URI })
                           .parse

      # The OIDC difference: the token response carries a signed `id_token`
      # (a JWT). We do NOT call a userinfo endpoint -- we verify this token.
      id_token = token_response['id_token']
      puts "ID TOKEN (raw JWT): #{id_token}\n"

      claims = verify_google_id_token(id_token)
      puts "VERIFIED CLAIMS: #{claims}\n"

      # The verified claims ARE the identity -- no extra network hop needed.
      session[:auth_info] = { 'name' => claims['name'],
                              'email' => claims['email'],
                              'email_verified' => claims['email_verified'],
                              'sub' => claims['sub'] }.to_json
      routing.redirect '/secret'
    end

    routing.get 'logout' do
      session[:auth_info] = nil
      routing.redirect '/'
    end
  end

  # Verify a Google-signed OIDC id_token and return its claims.
  #
  # This is exactly what every OIDC consumer must do, and it's the whole point
  # of the demo:
  #   1. read the token header (UNVERIFIED) to learn which key (`kid`) signed it;
  #   2. fetch Google's JSON Web Key Set (JWKS) and pick that public key;
  #   3. verify the RS256 signature with that key (Google dictates the
  #      algorithm; we use the OpenSSL-backed `jwt` gem for the RSA math);
  #   4. validate the `iss` / `aud` / `exp` claims ourselves.
  # If any step fails, we raise rather than trust the token.
  def verify_google_id_token(id_token)
    # 1. Peek at the header (UNVERIFIED) just to read the signing key id, then
    # 2+3. verify the RS256 signature + expiry with Google's matching key.
    _, header = JWT.decode(id_token, nil, false)
    claims, = JWT.decode(id_token, google_signing_key(header['kid']), true,
                         algorithms: ['RS256'], verify_expiration: true)

    # 4. Validate the issuer and audience ourselves. `aud` MUST equal our
    #    own client id -- this is what stops a token minted for some other
    #    app from being replayed against us.
    raise "Untrusted issuer: #{claims['iss']}" unless GOOGLE_ISSUERS.include?(claims['iss'])
    raise 'Audience mismatch' unless claims['aud'] == config.GOOGLE_CLIENT_ID

    claims
  end

  # Fetch Google's JWKS and return the public key whose `kid` signed the token.
  def google_signing_key(kid)
    jwks = JSON.parse(HTTP.get(GOOGLE_JWKS_URL).to_s)
    jwk = jwks['keys'].find { |key| key['kid'] == kid }
    raise 'No matching JWKS key for token kid' unless jwk

    JWT::JWK.import(jwk).verify_key
  end
end
