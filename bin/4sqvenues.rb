#!/usr/bin/env ruby

require_relative "../lib/4sq_category"
require_relative "../lib/4sq_client"
require_relative "../lib/4sq_formatter"
require_relative "../lib/4sq_options"
require_relative "../lib/zipcode"

require "thor"
require "ltsv"

require "diff-lcs"

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

class FoursquareVenuesCLI < Thor
  include FoursquareCategory
  include FoursquareClient
  include FoursquareFormatter
  extend  FoursquareOptions

  desc "add VENUE_NAME SUBVENUE_NAME", "add subvenue to venue"
  category_option
  # https://developer.foursquare.com/docs/api/venues/add
  def add(name, subvenue_name)
    subvenue = load(name).find {|e| e[:listName] == subvenue_name }

    if subvenue
      if subvenue[:url]
        warn "venue is already assigned for #{subvenue_name}: #{subvenue[:url]}"
        return
      end
    else
      warn "no subvenue name #{subvenue_name}"
      return
    end

    venue = client.venue(get_venue_id(name))
    #p venue

    # TODO:
    subvenue_option = {
      name: subvenue[:listName],
      ll: "#{venue.location.lat},#{venue.location.lng}",
      zip: venue.location.postalCode,
      state: venue.location.state,
      city:  venue.location.city,
      address: [ venue.name,  subvenue[:listAddress] ].join(" "),
      phone: subvenue[:listPhone],

    }
    p subvenue_option

    #client.add_venue(subvenue_option)

  end

  desc "view VENUE_NAME", "view venue list manged"
  option :crossStreet

  option :closed,    type: :boolean, default: false
  option :has_venue, type: :boolean, default: false
  option :no_venue,  type: :boolean, default: false

  option :search, desc: "only available with --no-venue", type: :boolean, default: false

  display_options(default_fields: %i[ name url zip state city address crossStreet phone ])
  def view(name)
    venues = load(name)

    venues.select! {|v| v[:listAddress] == options[:crossStreet] } if options[:crossStreet]
    venues.select! {|v| !v[:closed] } if options[:closed]
    venues.select! {|v| v[:url] }     if options[:has_venue]
    venues.select! {|v| !v[:url] }    if options[:no_venue]

    fields = %i[ listName listAddress listPhone ] + options[:fields] + %i[ closed ]
    if options[:no_venue] && options[:search]
      id = get_venue_id(name)
      parent_venue = client.venue(id)

      venues.each do |venue|
        found = client.search_venues(
          query:  venue[:listName],
          near:   "#{parent_venue["location"]["lat"]},#{parent_venue["location"]["lng"]}",
          intent: "match",
          limit:  1,
          radius: 1_000,
        )["venues"].first

        if found
          venue[:guessName] = found["name"]
          venue[:guessUrl]  = get_readable_value(found, "url")
        end
      end

      fields += %i[ guessName guessUrl ]
    end

    format(venues, fields, options[:format])
  end

  desc "subvenues VENUE_NAME", "get sub venues of venue"
  option :with_list,   type: :boolean, default: true
  option :guess_venue, type: :boolean, default: true
  option :update_list, type: :boolean, default: false

  display_options(default_fields: %i[ name url zip state city address crossStreet phone ])
  def subvenues(name)
    if options[:with_list]
      lists  = load(name) rescue []
      fields = %i[ listName listAddress listPhone ] + options[:fields]
    else
      lists = []
      fields = options[:fields]
    end
    lists   = (options[:with_list] ? (load(name) rescue []) : [])
    unknown = []

    id = get_venue_id(name)
    parent_venue = client.venue(id)

    grouped_venues = client.children(id)
    venues = grouped_venues.groups.map {|g| g.items }.flatten.sort {|a, b| a.name <=> b.name }

    if options[:guess_venue]
      venue_names = lists.map {|list| list[:listName].downcase }
    end

    venues.each do |venue|
      matched = lists.find {|v| v[:url]&.include?(venue["id"]) }

      if matched
        matched.update(compact_venue(venue, options[:fields]))
      else
        if options[:guess_venue]
          # parent_venue might be i10ned...s
          guessed_name = guess_venue_m17n(venue_names, venue["name"].downcase, ignore: name)
          if guessed_name
            guessed = lists.find {|v| v[:listName].downcase == guessed_name }

            unless guessed[:url]
              guessed.update(compact_venue(venue, options[:fields]))
            else
              warn "#{venue["name"]}(#{get_readable_value(venue, "url")}) matched to #{guessed[:name]}(#{guessed[:url]}) duplicate?"
              unknown.push({ listName: "", listAddress: "" }.merge(compact_venue(venue, options[:fields])))
            end
          else
            unknown.push({ listName: "", listAddress: "" }.merge(compact_venue(venue, options[:fields])))
          end
        else
          unknown.push({ listName: "", listAddress: "" }.merge(compact_venue(venue, options[:fields])))
        end
      end
    end

    save(name, lists) if options[:update_list]

    format(lists + unknown, fields, options[:format])
  end

  protected
  def config
    @config ||= YAML.load_file("./config/venues.yaml")
  end

  def get_venue_id(name)
    config[name]["id"] || raise("no venue found #{name}")
  end

  def save(name, venues)
    File.write("venues/#{name}.ltsv", venues.map {|v| LTSV.dump(v) }.join("\n"))
  end

  def load(name)
    LTSV.load("venues/#{name}.ltsv")
  end

  def guess_venue_m17n(names, name, ignore: "")
    if matched = name.match(/([^\(\)]+)\s\(([^\(\)]+)\)/)
      matched[1..2].map {|n| guess_venue(names, n, ignore: ignore) }.compact.first
    else
      guess_venue(names, name, ignore: ignore)
    end
  end

  def guess_venue(names, name, ignore: "")
    name = name.sub(ignore, "")

    guessed = names.max_by {|n| Diff::LCS.LCS(n.sub(ignore, ""), name).length }
    matched = Diff::LCS.LCS(guessed.sub(ignore, ""), name)

    if (1.0 * matched.length / [ guessed.sub(ignore, "").length, name.length ].min) > 0.7
      guessed
    else
      nil
    end
  end
end

FoursquareVenuesCLI.start
