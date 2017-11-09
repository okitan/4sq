#!/usr/bin/env ruby

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

class FoursquareVenues < Thor
  include FoursquareClient
  include FoursquareFormatter
  extend  FoursquareOptions

  desc "view VENUE_NAME", "view venue list manged"
  option :closed,   type: :boolean, default: false
  option :no_venue, type: :boolean, default: false

  option :search, desc: "only available with --no-venue", type: :boolean, default: false

  display_options(default_fields: %i[ name url zip state city address crossStreet ])
  def view(name)
    venues = load(name)

    venues.select! {|v| !v[:closed] } if options[:closed]
    venues.select! {|v| !v[:url] }    if options[:no_venue]

    fields = %i[ listName listAddress ] + options[:fields] + %i[ closed ]
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

  display_options(default_fields: %i[ name url zip state city address crossStreet ])
  def subvenues(name)
    if options[:with_list]
      lists  = load(name) rescue []
      fields = %i[ listName listAddress ] + options[:fields]
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

    venues.each do |venue|
      matched = lists.find {|v| v[:url]&.include?(venue["id"]) }

      if matched
        matched.update(compact_venue(venue, options[:fields]))
      else
        if options[:guess_venue]
          guessed = guess_venue(lists, venue["name"])
          if guessed
            unless guessed[:url]
              guessed.update(compact_venue(venue, options[:fields]))
            else
              warn "#{venue["name"]} matched to #{guessed["name"]} duplicate?"
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
    config[name] || raise("no venue found #{name}")
  end

  def save(name, venues)
    File.write("venues/#{name}.ltsv", venues.map {|v| LTSV.dump(v) }.join("\n"))
  end

  def load(name)
    LTSV.load("venues/#{name}.ltsv")
  end

  def guess_venue(venues, name)
    guess = venues.max_by {|v| Diff::LCS.LCS(v[:listName], name).length }
    matched = Diff::LCS.LCS(guess[:listName], name)

    if (1.0 * matched.length / [ guess[:listName].length, name.length ].min) > 0.7
      guess
    else
      if matched.size > 5
        #warn "check: '#{guess[:listName]}' with '#{name}'"
      end
      nil
    end
  end
end

FoursquareVenues.start
