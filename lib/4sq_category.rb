module FoursquareCategory
  module ClassMethods
    def frequenty_use_categories
    end

    def category_option
      option :category, enum: frequenty_use_categories
    end
  end

  def self.included(base)
    base.extend ClassMethods
  end

  protected
  def category_map
    @category_map ||= begin
      category_tree = client.venue_categories(includeSupportedCC: true)

      categories = category_tree.flat_map {|category| traverse_categories(category) }

      categories.each.with_object({}) do |category, hash|
        hash[category.name] = category.id
      end
    end
  end

  def traverse_categories(parent)
    if parent.categories.empty?
      parent
    else
      [ parent, *parent.categories.flat_map {|category| traverse_categories(category) } ]
    end
  end
end
