#!/usr/bin/env ruby

require_relative "../lib/4sq_client"
require_relative "../lib/4sq_category"

require "thor"

require "pry"
require "pp"

# suppress warning
Hashie.logger = Logger.new("/dev/null")

class FoursquareCategoryCLI < Thor
  include ::FoursquareCategory
  include ::FoursquareClient

  desc "get", "get categories"
  def get
    pp category_map
  end
end

FoursquareCategoryCLI.start
