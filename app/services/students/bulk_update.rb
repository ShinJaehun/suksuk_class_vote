module Students
  class BulkUpdate
    Result = Struct.new(:global_errors, :row_errors) do
      def success?
        global_errors.empty? && row_errors.empty?
      end
    end

    def initialize(classroom:, rows:, status:)
      @classroom = classroom
      @rows = rows
      @status = status
    end

    def call
      global_errors = []
      row_errors = {}
      Student.transaction do
        all_students = classroom.students.order(:id).lock.index_by { |student| student.id.to_s }
        students = all_students.slice(*row_ids)
        numbers = parsed_numbers
        validate_payload(all_students, students, numbers, global_errors, row_errors)
        validate_names(students, row_errors)
        raise ActiveRecord::Rollback if global_errors.any? || row_errors.any?

        temporary_start = [all_students.values.map(&:number).max.to_i, numbers.max.to_i].max + 1
        rows.each_with_index { |row, index| students.fetch(row["id"].to_s).update_columns(number: temporary_start + index) }
        rows.each_with_index { |row, index| students.fetch(row["id"].to_s).update!(number: numbers[index], name: row["name"].to_s.strip) }
      end
      Result.new(global_errors, row_errors)
    rescue ActiveRecord::RecordInvalid => e
      Result.new([e.record.errors.full_messages.to_sentence], {})
    rescue ActiveRecord::RecordNotUnique
      Result.new(["학생 번호가 다른 학생과 중복됩니다."], {})
    end

    private

    attr_reader :classroom, :rows, :status

    def row_ids
      rows.map { |row| row["id"].to_s }
    end

    def parsed_numbers
      rows.map { |row| Integer(row["number"], exception: false) }
    end

    def validate_payload(all_students, students, numbers, global_errors, row_errors)
      allowed_ids = all_students.values.select { |student| status == "all" || student.active? == (status == "active") }.map { |student| student.id.to_s }
      if rows.empty? || row_ids.uniq.size != rows.size || students.size != rows.size || (row_ids - allowed_ids).any?
        global_errors << "편집할 학생 정보가 올바르지 않습니다."
      end

      numbers.each_with_index do |number, index|
        add_row_error(row_errors, index, :number, "번호는 1 이상의 자연수여야 합니다.") if number.nil? || number < 1
      end
      numbers.each_index.group_by { |index| numbers[index] }.each_value do |indices|
        next unless indices.size > 1

        indices.each { |index| add_row_error(row_errors, index, :number, "같은 번호가 입력되었습니다.") }
      end
      reserved_numbers = all_students.except(*row_ids).values.map(&:number)
      numbers.each_with_index do |number, index|
        add_row_error(row_errors, index, :number, "이미 사용 중인 번호입니다.") if reserved_numbers.include?(number)
      end
    end

    def validate_names(students, row_errors)
      rows.each_with_index do |row, index|
        student = students[row["id"].to_s]
        next unless student

        student.name = row["name"].to_s.strip
        next if student.valid?

        student.errors.full_messages_for(:name).each { |message| add_row_error(row_errors, index, :name, message) }
      end
    end

    def add_row_error(row_errors, index, field, message)
      row_errors[index] ||= {}
      row_errors[index][field] ||= []
      row_errors[index][field] << message unless row_errors[index][field].include?(message)
    end
  end
end
