#!/usr/bin/env ruby

require "thor"

require "foursquare2"

require "pry"

class Foursquare < Thor
  desc "show *VENUE_ID", "show venues"
  def show(*venues)
    venues.each do |id|
      p client.venue(id)
    end
  end

  # https://developer.foursquare.com/docs/api/venues/flag
  desc "delete *VENUE_ID", "delete venues"
  option :reason, desc: "reason of delete", default: "doesnt_exist",
                  enum: %w[ mislocated closed duplicate inappropriate doesnt_exist event_over ]
  def delete(*venues)
    venues.each do |id|
      p client.flag_venue(id, problem: options[:reason])
    end
  end

  protected
  def client
    @client ||= Foursquare2::Client.new(oauth_token: ENV["ACCESS_TOKEN"], api_version: "20170801")
  end
end

Foursquare.start
