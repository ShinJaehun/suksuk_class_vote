module ParticipantGroups
  class UpdateRoster
    Result = Struct.new(:success?, :errors, :slot_rows, :new_slot_rows, keyword_init: true)

    def initialize(participant_group:, slot_attributes:, new_slot_attributes: {})
      @participant_group = participant_group
      @slot_rows = normalize_rows(slot_attributes, existing: true)
      @new_slot_rows = normalize_rows(new_slot_attributes, existing: false)
      @errors = []
    end

    def call
      validate_rows
      return failure if errors.any?

      ParticipantSlot.transaction do
        participant_group.with_lock do
          slots = participant_group.participant_slots.lock.order(:id).to_a
          validate_slot_ids(slots)
          raise ActiveRecord::Rollback if errors.any?

          move_to_temporary_numbers(slots)
          apply_existing_rows(slots.index_by { |slot| slot.id.to_s })
          create_new_rows
        end
      end

      errors.any? ? failure : success
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      errors << "학생 명단을 저장할 수 없습니다. 번호와 이름을 확인해 주세요."
      failure
    end

    private

    attr_reader :participant_group, :slot_rows, :new_slot_rows, :errors

    def normalize_rows(attributes, existing:)
      attributes.to_h.values.map do |attributes_row|
        row = attributes_row.to_h.stringify_keys.slice("id", "number", "name", "_destroy")
        row["id"] = row["id"].to_s if existing
        row["number"] = row["number"].to_s.strip
        row["name"] = row["name"].to_s.strip
        row["_destroy"] = row["_destroy"].to_s
        row
      end
    end

    def validate_rows
      new_slot_rows.reject! { |row| row["number"].blank? && row["name"].blank? }
      active_rows = slot_rows.reject { |row| destroy?(row) } + new_slot_rows

      active_rows.each do |row|
        number = integer_number(row["number"])
        errors << "학생 번호는 1 이상의 숫자여야 합니다." if number.blank? || number < 1
        errors << "학생 이름을 입력해 주세요." if row["name"].blank?
      end

      numbers = active_rows.filter_map { |row| integer_number(row["number"]) }
      errors << "같은 번호가 있습니다." if numbers.size != numbers.uniq.size
      errors.uniq!
    end

    def validate_slot_ids(slots)
      submitted_ids = slot_rows.map { |row| row["id"] }.sort
      errors << "학생 명단 정보가 올바르지 않습니다." unless submitted_ids == slots.map { |slot| slot.id.to_s }.sort
    end

    def move_to_temporary_numbers(slots)
      desired_numbers = (slot_rows + new_slot_rows).filter_map { |row| integer_number(row["number"]) }
      temporary_base = [slots.map(&:number).max.to_i, desired_numbers.max.to_i].max + 10_000

      slots.each_with_index do |slot, index|
        slot.update_columns(number: temporary_base + index)
      end
    end

    def apply_existing_rows(slots_by_id)
      slot_rows.each do |row|
        slot = slots_by_id.fetch(row["id"])
        if destroy?(row)
          slot.destroy!
        else
          slot.update!(number: integer_number(row["number"]), name: row["name"])
        end
      end
    end

    def create_new_rows
      new_slot_rows.each do |row|
        participant_group.participant_slots.create!(
          number: integer_number(row["number"]),
          name: row["name"]
        )
      end
    end

    def integer_number(value)
      Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end

    def destroy?(row)
      row["_destroy"] == "1"
    end

    def success
      Result.new(success?: true, errors: [], slot_rows: slot_rows, new_slot_rows: new_slot_rows)
    end

    def failure
      Result.new(success?: false, errors: errors, slot_rows: slot_rows, new_slot_rows: new_slot_rows)
    end
  end
end
