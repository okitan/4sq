#!/usr/bin/env ruby

require "thor"

require "foursquare2"

require_relative "zipcode"

require "pry"

module Foursquare2
  module Venues
    # undocumented
    def children(venue_id, options = {})
      response = connection.get do |req|
        req.url "venues/#{venue_id}/children", options
      end
      return_error_or_body(response, response.body.response.children)
    end
  end
end

# suppress warning
Hashie.logger = Logger.new("/dev/null")

class Foursquare < Thor
  class << self
    def display_options
      option :fields, type: :array, default: %w[ name url zip state city address crossStreet phone stats categories ]
      option :format, aliases: "-f", default: "table", enum: %w[ table ltsv csv ]
    end
  end

  desc "show *VENUE_ID", "show venues"
  display_options
  def show(*venues)
    format(venues.map {|id| compact_venue(client.venue(id), options[:fields]) }, options[:fields], options[:format])
  end

  desc "fix *VENUE_ID", "show venues"
  option :parentId, desc: "parent venue id (addresses will be copied from here)"
  option :state
  option :city
  option :address
  option :crossStreet

  option :auto,    type: :boolean, default: false
  option :dry_run, type: :boolean, default: true
  option :format, aliases: "-f", default: "table", enum: %w[ table ltsv csv ]
  def fix(*venues)
    venues = venues.map {|id| client.venue(id) }

    patches = if options[:parentId]
      parent_venue = client.venue(options[:parentId])

      venues.map do |venue|
        %i[ zip state city address crossStreet ].each.with_object("parentId" => options[:parentId]) do |key, hash|
          hash[key.to_s] = get_readable_value(parent_venue, key) unless (get_readable_value(venue, key) || "") == get_readable_value(parent_venue, key)
        end
      end
    elsif options[:auto]
      venues.map {|venue| diff(venue, options[:fields]) }
    end

    %i[ state city address crossStreet ].each do |key|
      if options[key]
        patches.each {|patch| patch[key.to_s] = options[key] }
      end
    end

    venues.zip(patches).each do |venue, patch|
      if options[:dry_run]
        puts get_readable_value(venue, "name")
        show_changes(venue, patch)
      else
        unless patch.empty?
          # TODO: emit fields to be updated
          client.propose_venue_edit(venue["id"], patch)

          fields = (%w[ name url ] + patch.keys).uniq
          format([ compact_venue(client.venue(venue["id"]), fields) ], fields, options[:format])
        end
      end
    end
  end

  # https://developer.foursquare.com/docs/api/venues/search
  desc "search VENUE_NAME", "search by venue name"
  option :near,   desc: "name of town", default: "Kawasaki"
  option :intent, desc: "sort",         default: "browse",   enum: %w[ browse match checkin global ]

  option :limit, desc: "number of results (max 50)",  default: 10

  display_options
  def search(word)
    venues = client.search_venues(
      query:  word,
      near:   options[:near],
      intent: options[:intent],
      limit:  options[:limit],
      radius: 10_000,
    )["venues"]

    format(venues.map {|venue| compact_venue(venue, options[:fields]) }, options[:fields], options[:format])
  end

  desc "subvenues VENUE_ID", "get sub venues of venue"
  option :show_near_venues, type: :boolean, default: false

  option :limit, desc: "number of results (max 50)",  default: 50
  display_options
  def subvenues(id)
    parent_venue = client.venue(id)

    grouped_venues = client.children(id)
    venues = grouped_venues.groups.map {|g| g.items }.flatten.sort {|a, b| a.name <=> b.name }

    format(venues.map {|venue| compact_venue(venue, options[:fields]) }, options[:fields], options[:format])
  end

  desc "close *VENUE_ID", "close venues"
  def close(*venues)
    venues.each do |id|
      p client.flag_venue(id, problem: "closed")
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
    @client ||= Foursquare2::Client.new(
      oauth_token: ENV["ACCESS_TOKEN"], api_version: "20170801",
      #connection_middleware: [ FaradayMiddleware::FollowRedirects ]
    )
  end

  def format(venues, fields, format)
    return if venues.empty?

    case format
    when "table"
      require "hirb-unicode"
      puts Hirb::Helpers::AutoTable.render(venues, resize: false, fields: fields)
    when "ltsv"
      require "ltsv"
      venues.each {|v| puts LTSV.dump(v) }
    when "csv"
      require "csv"
      warn CSV.generate_line(venues.first.keys)
      venues.each {|v| puts CSV.generate_line(v.values) }
    end
  end

  def show_changes(venue, patch)
    require "hirb-unicode"
    changes = patch.map do |key, value|
      { "key" => key, "before" => get_readable_value(venue, key), "after" => value }
    end

    puts Hirb::Helpers::AutoTable.render(changes, resize: false, fields: %w[ key before after ])
  end

  def compact_venue(venue, fields)
    fields.each.with_object({}) do |field, hash|
      hash[field] = get_readable_value(venue, field)
    end
  end

  def get_readable_value(venue, field)
    case field.to_s
    when "url"
      venue["shortUrl"] ||"https://ja.foursquare.com/v/#{venue["id"]}"
    when "zip"
      venue["location"]["postalCode"]&.sub("-", "")
    when "state"
      venue["location"]["state"]
    when "city"
      city = venue["location"]["city"]

      # 東京, 東京都
      if city == "東京"
        address, city = *venue["location"]["formattedAddress"]
        city&.split(",").first
      else
        city
      end
    when "address"
      venue["location"]["address"]
    when "crossStreet"
      venue["location"]["crossStreet"]
    when "fullAddress"
      address, city = *venue["location"]["formattedAddress"]
      # address includes m17ned (crossStreet)
      [ city&.split(",")&.reverse&.join(""), address ].compact.join("")
    when "phone"
      venue["contact"]["phone"]
    when "stats"
      "#{venue["stats"]["checkinsCount"]}/#{venue["stats"]["usersCount"]}"
    when "categories"
      venue["categories"].map {|c| c["name"] }
    else
      venue[field]
    end
  end

  def diff(venue, fields)
    ret = {}

    # zip / state / city / address / crossStreet
    address = %i[ state city address crossStreet fullAddress ].each.with_object({}) do |k, h|
      h[k] = get_readable_value(venue, k)
    end

    begin
      zip = Zipcode.search_town(address[:state], address[:city], address[:address])
      ret["zip"] = zip unless zip == get_readable_value(venue, "zip")

      new_address = adjust_address_4sq(address)
      %i[ state city address crossStreet ].each do |key|
        ret[key.to_s] = new_address[key] unless (address[key] || "") == new_address[key]
      end
    rescue => e
      warn e

      begin
        zip = Zipcode.search(address[:fullAddress])
        ret["zip"] = zip unless zip == get_readable_value(venue, "zip")

        _state, _city, _address = *Zipcode.split_address(address[:fullAddress])
        new_address = adjust_address_4sq(state: _state, city: _city, address: _address, crossStreet: address[:crossStreet])
        %i[ state city address crossStreet ].each do |key|
          ret[key.to_s] = new_address[key] unless (address[key] || "") == new_address[key]
        end
      rescue => e
        warn e
      end
    end

    ret
  end

  def adjust_address_4sq(state:, city:, address:, crossStreet: nil, **_)
    crossStreet ||= ""

    address = address.tr("０-９", "0-9").gsub(/ー|丁目/, "-")

    i = address.rindex(/\d/)
    if i
      address, crossStreet = address[0..i], ((address[i+1..-1] || "") + crossStreet)
    end

    if state != "東京都" && city.end_with?("区")
      i = city.index("市")
      city, address = city[0..i], ((city[i+1..-1] || "") + address)
    end

    { state: state, city: city, address: address, crossStreet: crossStreet }
  end
end

Foursquare.start
