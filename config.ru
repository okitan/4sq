require "sinatra"
require "omniauth-foursquare"

require "pry"

class MyApp < ::Sinatra::Base
  configure do
    set :sessions, true
  end

  use OmniAuth::Builder do
    provider :foursquare, ENV["CLIENT_ID"], ENV["CLIENT_SECRET"]
  end

  get "/" do
    "hello"
  end

  get "/auth/foursquare/callback" do
    headers["Content-Type"] = "application/json"
    MultiJson.dump(request.env["omniauth.auth"], pretty: true)
  end
end

run MyApp
