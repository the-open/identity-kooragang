module IdentityKooragang
  class ReadOnly < ApplicationRecord
    self.abstract_class = true
    establish_connection(Settings.kooragang.read_only_database_url) if Settings.kooragang.read_only_database_url
  end
end
