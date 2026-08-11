require "securerandom"

module Teachers
  module TemporaryPassword
    CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".freeze
    LENGTH = 8

    module_function

    def generate(login_id:)
      loop do
        password = Array.new(LENGTH) { CHARACTERS[SecureRandom.random_number(CHARACTERS.length)] }.join
        return password unless password.casecmp?(login_id.to_s.strip)
      end
    end
  end
end
