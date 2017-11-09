module FoursquareFormatter
  protected

  def format(venues, fields, format)
    return if venues.empty?

    case format.to_sym
    when :table
      require "hirb-unicode"
      puts Hirb::Helpers::AutoTable.render(venues, resize: false, fields: fields.map(&:to_sym))
    when :ltsv
      require "ltsv"
      venues.each {|v| puts LTSV.dump(v) }
    when :csv
      require "csv"
      warn CSV.generate_line(venues.first.keys)
      venues.each {|v| puts CSV.generate_line(v.values) }
    end
  end

  def compact_venue(venue, fields)
    fields.each.with_object({}) do |field, hash|
      hash[field.to_sym] = get_readable_value(venue, field)
    end
  end

  def get_readable_value(venue, field)
    case field.to_sym
    when :url
      venue["shortUrl"] ||"https://ja.foursquare.com/v/#{venue["id"]}"
    when :zip
      venue["location"]["postalCode"]&.sub("-", "")
    when :state
      venue["location"]["state"]
    when :city
      city = venue["location"]["city"]

      # 東京, 東京都
      if city == "東京"
        address, city = *venue["location"]["formattedAddress"]
        city&.split(",").first
      else
        city
      end
    when :address
      venue["location"]["address"]
    when :crossStreet
      venue["location"]["crossStreet"]
    when :fullAddress
      address, city = *venue["location"]["formattedAddress"]
      # address includes m17ned (crossStreet)
      [ city&.split(",")&.reverse&.join(""), address ].compact.join("")
    when :phone
      venue["contact"]["phone"]
    when :stats
      "#{venue["stats"]["checkinsCount"]}/#{venue["stats"]["usersCount"]}"
    when :categories
      venue["categories"].map {|c| c["name"] }
    else
      venue[field.to_s]
    end
  end
end
