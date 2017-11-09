#!/usr/bin/env ruby

require "yaml"

module Zipcode
  def split_address(address)
    regexp = /(...??[都道府県])((?:旭川|伊達|石狩|盛岡|奥州|田村|南相馬|那須塩原|東村山|武蔵村山|羽村|十日町|上越|富山|野々市|大町|蒲郡|四日市|姫路|大和郡山|廿日市|下松|岩国|田川|大村)市|.+?郡(?:玉村|大町|.+?)[町村]|.+?市.+?区|.+?[市区町村])(.+)/

    address.match(regexp).captures
  end

  def search(address)
    begin
      ken, shi, tyou = split_address(address)
    rescue
      raise "no match #{address}"
    end

    search_town(ken, shi, tyou)
  end

  def search_town(ken, shi, tyou, banti = nil)
    if dictionary[ken]
      if dictionary[ken][shi]
        if dictionary[ken][shi][tyou]
          group_zipcode(dictionary[ken][shi][tyou])
        else
          tyou = tyou.tr("０-９", "0-9")
          i = tyou.index(/\d/)

          unless i
            towns = dictionary[ken][shi].keys.select {|town| town.start_with?(tyou) }
            if towns.size == 1
              return search_town(ken, shi, towns.first)
            else
              if towns.size > 2
                raise "#{towns.size} candidates found: #{ken} #{shi} #{tyou}"
              else
                raise "unknown town: #{ken} #{shi} #{tyou}?"
              end
            end
          end

          tyou, banti = tyou[0..i-1], tyou[i..-1]

          if dictionary[ken][shi][tyou]
            if dictionary[ken][shi][tyou][banti]
              dictionary[ken][shi][tyou][banti]
            elsif dictionary[ken][shi][tyou]["その他"]
              dictionary[ken][shi][tyou]["その他"]
            else
              group_zipcode(dictionary[ken][shi][tyou])
            end
          else
            raise "unknown town: #{ken} #{shi} #{tyou}? #{banti}"
          end
        end
      else
        raise "unknown city: #{ken} #{shi}? #{tyou}"
      end
    else
      raise "unknown state: #{ken}? #{shi} #{tyou}"
    end
  end

  def group_zipcode(hash)
    return hash unless hash.is_a?(Hash)

    hash.each.with_object(Hash.new { [] }) do |(key, value), h|
      h[value] << key
    end
  end

  def dictionary
    @dictionary ||= YAML.load_file("data/KEN_ALL.rev.yaml")
  end

  module_function *instance_methods
end
