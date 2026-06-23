# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Development/test-only admin account. Production admins must be created explicitly.
if Rails.env.development? || Rails.env.test?
  User.find_or_create_by!(email: "a@a") do |user|
    user.password = "password"
    user.name = "관리자"
    user.role = :admin
  end
end
