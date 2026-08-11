class AddColorKeyToSchools < ActiveRecord::Migration[8.1]
  COLOR_KEYS = %w[rose amber emerald sky violet].freeze

  def up
    add_column :schools, :color_key, :string

    quoted_keys = COLOR_KEYS.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      UPDATE schools
      SET color_key = (ARRAY[#{quoted_keys}])[((id - 1) % #{COLOR_KEYS.length}) + 1]
    SQL

    change_column_null :schools, :color_key, false
    add_check_constraint :schools,
                         "color_key IN (#{quoted_keys})",
                         name: "schools_color_key_allowed"
  end

  def down
    remove_check_constraint :schools, name: "schools_color_key_allowed"
    remove_column :schools, :color_key
  end
end
