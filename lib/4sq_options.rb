module FoursquareOptions
  def display_options(default_fields: %i[ name url zip state city address crossStreet phone stats categories ])
    option :fields, type: :array, default: default_fields
    option :format, aliases: "-f", default: :table, enum: %i[ table ltsv csv ]
  end
end
