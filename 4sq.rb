#!/usr/bin/env ruby

require "thor"

require "foursquare2"

require "pry"

# suppress warning
Hashie.logger = Logger.new("/dev/null")

class Foursquare < Thor
  desc "show *VENUE_ID", "show venues"
  def show(*venues)
    venues.each do |id|
      p client.venue(id)
    end
  end

  # https://developer.foursquare.com/docs/api/venues/search
  desc "search VENUE_NAME", "search by venue name"
  option :near,   desc: "name of town", default: "Kawasaki"
  option :intent, desc: "sort",         default: "browse",   enum: %w[ browse match checkin global ]

  option :limit, desc: "number of results (max 50)",  default: 10

  option :fields, typa: :array, default: %w[ name url categories ]
  option :format, aliases: "-f", default: "table", enum: %w[ table ltsv csv ]
  def search(word)
    venues = client.search_venues(
      query:  word,
      near:   options[:near],
      intent: options[:intent],
      limit:  options[:limit],
      radius: 100_000,
    )["venues"]

    format(venues, options[:fields], options[:format])
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

  def format(venues, fields, format, first: false)
    venues = [*venues]

    return if venues.empty?

    venues = venues.map do |venue|
      fields.each.with_object({}) do |field, hash|
        hash[field] = get_readable_value(venue, field)
      end
    end

    case format
    when "table"
      require "hirb-unicode"
      puts Hirb::Helpers::AutoTable.render(venues, resize: false)
    when "ltsv"
      require "ltsv"
      venues.each {|v| puts LTSV.dump(v) }
    when "csv"
      require "csv"
      warn CSV.generate_line(venues.first.keys)
      venues.each {|v| puts CSV.generate_line(v.values) }
    end
  end

  def get_readable_value(venue, field)
    case field
    when "url"
      "https://ja.foursquare.com/v/#{venue["id"]}"
    when "categories"
      venue["categories"].map {|c| c["name"] }
    else
      venue[field]
    end
  end
end

Foursquare.start
