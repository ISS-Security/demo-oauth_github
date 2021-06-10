# frozen_string_literal: true

# Roda web app demonstrating Github OAuth
# Install:
# - clone this repo
# - rbenv install 2.6.2
# - gem install bundler:2.0.1
# - bundle
# - setup OAuth app for Github and get Github id/secret
# - put OAuth id/secret in config/secrets.yml
#
# Run using: rackup -p 4567

require 'roda'
require 'econfig'
require 'http'

# Demo app for three-legged OAuth
class OAuthDemo < Roda
  plugin :environments

  extend Econfig::Shortcut
  Econfig.env = environment.to_s
  Econfig.root = '.'

  ONE_MONTH = 30 * 24 * 60 * 60 # in seconds

  use Rack::Session::Cookie, expire_after: ONE_MONTH, secret: 'not-a-secret'

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

    routing.get 'login' do
      url = 'https://github.com/login/oauth/authorize'
      scope = 'user:email'
      oauth_params = ["client_id=#{config.GH_CLIENT_ID}",
                      "scope=#{scope}"].join('&')
      "<a href='#{url}?#{oauth_params}'> Login with Github</a>"
    end

    routing.get 'github_callback' do
      result = HTTP.headers(accept: 'application/json')
                   .post('https://github.com/login/oauth/access_token',
                         form: { client_id: config.GH_CLIENT_ID,
                                 client_secret: config.GH_CLIENT_SECRET,
                                 code: routing.params['code'] })
                   .parse

      puts "ACCESS TOKEN: #{result}\n"

      gh_account = HTTP.headers(user_agent: 'OAuth Demo',
                                authorization: "token #{result['access_token']}",
                                accept: 'application/json')
                       .get('https://api.github.com/user')
                       .parse

      puts "GITHUB ACCOUNT: #{gh_account}"

      session[:auth_info] = gh_account.to_json
      routing.redirect '/secret'
    end

    routing.get 'logout' do
      session[:auth_info] = nil
      routing.redirect '/'
    end
  end
end
