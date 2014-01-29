module Core
  module Helpers
    extend self

    def admin_user?
      current_user.try(:email) == 'leslieviljoen@gmail.com'
    end
  end
end
