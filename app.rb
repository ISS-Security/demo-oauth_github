# Classic style Ruby app demonstrating Github OAuth
# Run using `$ ruby app.rb`

require 'sinatra'
require 'config_env'
require 'http'

ConfigEnv.path_to_config("#{__dir__}/config_env.rb")
use Rack::Session::Cookie, secret: 'sdafljk'

get '/login' do
  "<a href='https://github.com/login/oauth/authorize?"\
    "client_id=#{ENV['GH_CLIENT_ID']}&"\
    "scope=user:email'> Login with Github</a>"
end

get '/callback' do
  result = HTTP.headers(accept: 'application/json')
               .post('https://github.com/login/oauth/access_token',
                     form: { client_id: ENV['GH_CLIENT_ID'],
                             client_secret: ENV['GH_CLIENT_SECRET'],
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

get '/secret' do
  unless session[:auth_info]
    redirect '/login'
    halt
  end

  account = JSON.load(session[:auth_info])

  "Your best and worst friend is #{account['name']} at #{account['email']}"\
  "<BR><a href='/logout'>logout</a>"
end

get '/logout' do
  session[:auth_info] = nil
  redirect '/'
end

get '/' do
  '<a href="/secret">See the secret page</a>'
end
