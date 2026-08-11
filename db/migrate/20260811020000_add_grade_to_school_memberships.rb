class AddGradeToSchoolMemberships < ActiveRecord::Migration[8.1]
  def up
    add_column :school_memberships, :grade, :integer

    execute <<~SQL.squish
      UPDATE school_memberships
      SET grade = classrooms.grade
      FROM classrooms
      WHERE classrooms.teacher_id = school_memberships.user_id
        AND classrooms.school_id = school_memberships.school_id
        AND classrooms.active = TRUE
    SQL

    add_check_constraint :school_memberships,
                         "grade IS NULL OR grade BETWEEN 1 AND 6",
                         name: "school_memberships_grade_allowed"
    add_index :school_memberships, %i[school_id grade]
  end

  def down
    remove_index :school_memberships, %i[school_id grade]
    remove_check_constraint :school_memberships, name: "school_memberships_grade_allowed"
    remove_column :school_memberships, :grade
  end
end
