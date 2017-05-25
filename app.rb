# Classic style Ruby app demonstrating Github OAuth
# Run using `$ rackup -p 4567`

require 'econfig'
require 'sinatra'
require 'http'

# Demo app for three-legged OAuth
class OAuthDemo < Sinatra::Base
  extend Econfig::Shortcut
  use Rack::Session::Cookie, secret: 'sdafljk'

  configure do
    Econfig.env = settings.environment.to_s
    Econfig.root = File.expand_path('.', settings.root)
  end

  get '/' do
    '<a href="/secret">See the secret page</a>'
  end

  get '/secret' do
    unless session[:auth_info]
      redirect '/login'
      halt
    end

    account = JSON.parse(session[:auth_info])

    "Your best and worst friend is #{account['name']} at #{account['email']}"\
    "<BR><a href='/logout'>logout</a>"
  end

  get '/login' do
    url = 'https://github.com/login/oauth/authorize'
    scope = 'user:email'
    params = ["client_id=#{settings.config.GH_CLIENT_ID}",
              "scope=#{scope}"]
    "<a href='#{url}?#{params.join('&')}'> Login with Github</a>"
  end

  get '/github_callback' do
    result = HTTP.headers(accept: 'application/json')
                 .post('https://github.com/login/oauth/access_token',
                       form: { client_id: settings.config.GH_CLIENT_ID,
                               client_secret: settings.config.GH_CLIENT_SECRET,
                               code: params['code'] })
                 .parse

    puts "ACCESS TOKEN: #{result}"

    gh_account = HTTP.headers(user_agent: 'Config Secure',
                              authorization: "token #{result['access_token']}",
                              accept: 'application/json')
                     .get('https://api.github.com/user')
                     .parse

    puts "GITHUB ACCOUNT: #{gh_account}"

    session[:auth_info] = gh_account.to_json
    redirect '/secret'
  end

  get '/logout' do
    session[:auth_info] = nil
    redirect '/'
  end
end
