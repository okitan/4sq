require 'rake/clean'

require "csv"
require "yaml"

require "pry"

CLOBBER.replace(%w[ KEN_ALL.zip KEN_ALL.CSV KEN_ALL.yaml ])

task download: %i[ clobber ] do
  `wget http://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip`
end

task unzip: %i[ download ] do
  `unzip ken_all.zip`
end

task :normalize do
  lines = CSV.read("KEN_ALL.CSV", encoding: "SJIS")

  # Kyoto sucks
  keep = nil
  result = lines.each.with_object({}) do |data, hash|
    _, _, zipcode, _, _, _, ken, shi, tyou, has_many_zipcodes, use_koaza, *rest = *data

    # normalize
    ken.encode!("UTF-8")
    shi.encode!("UTF-8")
    tyou.encode!("UTF-8")

    has_many_zipcodes = (has_many_zipcodes == "1")
    #use_koaza         = (use_koaza == "1") # I don't know how to use it

    if keep
      tyou = keep + tyou
      keep = nil
    end

    options = nil
    if tyou.include?("（")
      unless tyou.include?("）")
        keep = tyou
        next
      end

      tyou, option = tyou.split("（")
      option = option[0..-2] # remove "）"

      if option == "番地" || option == "丁目"
        options = [ option ]
      else
        option = option.split(/番地|丁目/).first

        if option
          options = option.tr("０-９", "0-9").split("、").map do |item|
            if item.include?("～") # Note: 文字コードむずかしいよね
              s, e = *item.split("～")
              (s.to_i..e.to_i).map(&:to_s)
            else
              item
            end
          end.flatten
        else
        end
      end
    end

    hash[zipcode] = { ken: ken, shi: shi, tyou: tyou }
    hash[zipcode][:options] = options if options
  end

  YAML.dump(result, File.open("KEN_ALL.yaml", 'w'))
end

# See: http://www.post.japanpost.jp/zipcode/dl/readme.html
desc "convert"
#task convert: %i[ unzip ] do
task :convert do
  zipcode_address_map = YAML.load_file("KEN_ALL.yaml")

  result = zipcode_address_map.each.with_object(Hash.new { |h1,k1| h1[k1] = Hash.new { |h2,k2| h2[k2] = {} } }) do |(zipcode, address), hash|
    if address[:options]
      if hash[address[:ken]][address[:shi]][address[:tyou]]
        unless hash[address[:ken]][address[:shi]][address[:tyou]].is_a?(Hash)
          hash[address[:ken]][address[:shi]][address[:tyou]] = { "" => hash[address[:ken]][address[:shi]][address[:tyou]] }
        end
      else
        hash[address[:ken]][address[:shi]][address[:tyou]] = {}
      end

      address[:options].each do |option|
        hash[address[:ken]][address[:shi]][address[:tyou]][option] = zipcode
      end
    else
      if hash[address[:ken]][address[:shi]][address[:tyou]]
        begin
          hash[address[:ken]][address[:shi]][address[:tyou]][""] = zipcode
        rescue => e
          if address[:tyou] == "東栄町" # fucking niigata
            # https://ja.wikipedia.org/wiki/%E5%8C%97%E5%8C%BA_(%E6%96%B0%E6%BD%9F%E5%B8%82)#.E4.BD.8F.E5.B1.85.E8.A1.A8.E7.A4.BA
            hash[address[:ken]][address[:shi]][address[:tyou]] = "9503323"
          else
            raise e
          end
        end
      else
        hash[address[:ken]][address[:shi]][address[:tyou]] = zipcode
      end
    end
  end

  YAML.dump(result, File.open("KEN_ALL.rev.yaml", 'w'))
end
