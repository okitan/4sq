#!/usr/bin/env ruby

require "thor"

require_relative "../lib/zipcode"

class ZipCodeCLI < Thor
  desc "search ADDRESS", "search address"
  def search(address)
    puts Zipcode.search(address)
  end
end

ZipCodeCLI.start
