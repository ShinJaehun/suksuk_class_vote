class LimitTeacherToOneActiveClassroom < ActiveRecord::Migration[8.1]
  def change
    remove_index :classrooms,
                 :teacher_id,
                 unique: true,
                 name: "index_classrooms_on_teacher_id"

    add_index :classrooms,
              :teacher_id,
              unique: true,
              where: "active = TRUE AND teacher_id IS NOT NULL",
              name: "idx_classrooms_on_active_teacher"
  end
end
