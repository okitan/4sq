#!/usr/bin/env ruby

require_relative "../lib/4sq_client"
require_relative "../lib/4sq_formatter"
require_relative "../lib/4sq_options"
require_relative "../lib/zipcode"

require "thor"
require "pry"

# suppress warning
Hashie.logger = Logger.new("/dev/null")

class FoursquareCLI < Thor
  include FoursquareClient
  include FoursquareFormatter
  extend  FoursquareOptions

  desc "show *VENUE_ID", "show venues"
  display_options
  def show(*venues)
    format(venues.map {|id| compact_venue(client.venue(id), options[:fields]) }, options[:fields], options[:format])
  end

  desc "fix *VENUE_ID", "show venues"
  option :name

  option :parent,   desc: "parent venue name (resolve its id from config)"
  option :parentId, desc: "parent venue id (addresses will be copied from here)"
  option :state
  option :city
  option :address
  option :crossStreet

  option :auto,    type: :boolean, default: false
  option :dry_run, type: :boolean, default: true
  option :format, aliases: "-f", default: :table, enum: %i[ table ltsv csv ]
  def fix(*venues)
    venues = venues.map {|id| client.venue(id) }

    patches = if parent_id = (options[:parent] ? YAML.load_file("./config/venues.yaml")[options[:parent]]["id"] : options[:parentId])
      parent_venue = client.venue(parent_id)

      venues.map do |venue|
        %i[ zip state city address ].each.with_object(parentId: parent_id) do |key, hash|
          hash[key] = get_readable_value(parent_venue, key) unless (get_readable_value(venue, key) || "") == get_readable_value(parent_venue, key)
        end
      end
    elsif options[:auto]
      venues.map {|venue| diff(venue, options[:fields]) }
    end

    %i[ name state city address ].each do |key|
      if options[key]
        patches.each {|patch| patch[key] = options[key] }
      end
    end
    if options[:crossStreet]
      patches.each {|patch| patch[:crossStreet] = [ options[:parent], options[:crossStreet] ].compact.join(" ") }
    end

    venues.zip(patches).each do |venue, patch|
      if options[:dry_run]
        puts get_readable_value(venue, "name")
        show_changes(venue, patch)
      else
        unless patch.empty?
          # TODO: emit fields to be updated
          client.propose_venue_edit(venue["id"], patch)

          fields = (%i[ name url ] + patch.keys.map(&:to_sym)).uniq
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
  def show_changes(venue, patch)
    require "hirb-unicode"
    changes = patch.map do |key, value|
      { key: key, before: get_readable_value(venue, key), after: value }
    end

    puts Hirb::Helpers::AutoTable.render(changes, resize: false, fields: %i[ key before after ])
  end

  def diff(venue, fields)
    ret = {}

    # zip / state / city / address / crossStreet
    address = %i[ state city address crossStreet fullAddress ].each.with_object({}) do |k, h|
      h[k] = get_readable_value(venue, k)
    end

    begin
      zip = Zipcode.search_town(address[:state], address[:city], address[:address])
      ret[:zip] = zip unless zip == get_readable_value(venue, :zip)

      new_address = adjust_address_4sq(address)
      %i[ state city address crossStreet ].each do |key|
        ret[key] = new_address[key] unless (address[key] || "") == new_address[key]
      end
    rescue => e
      warn e

      begin
        zip = Zipcode.search(address[:fullAddress])
        ret[:zip] = zip unless zip == get_readable_value(venue, :zip)

        _state, _city, _address = *Zipcode.split_address(address[:fullAddress])
        new_address = adjust_address_4sq(state: _state, city: _city, address: _address, crossStreet: address[:crossStreet])
        %i[ state city address crossStreet ].each do |key|
          ret[key] = new_address[key] unless (address[key] || "") == new_address[key]
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

FoursquareCLI.start
