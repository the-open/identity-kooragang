module IdentityKooragang
  class ReadWrite < ApplicationRecord
    self.abstract_class = true
    establish_connection(Settings.kooragang.database_url) if Settings.kooragang.database_url
  end
end
