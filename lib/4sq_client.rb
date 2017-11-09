require "foursquare2"

module FoursquareClient
  protected
   def client
    @client ||= Foursquare2::Client.new(
      oauth_token: ENV["ACCESS_TOKEN"], api_version: "20171101",
      #connection_middleware: [ FaradayMiddleware::FollowRedirects ]
    )
  end
end
