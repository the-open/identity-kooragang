module IdentityKooragang
  module ReadOnly
    def self.included(mod)
      mod.establish_connection Settings.kooragang.read_only_database_url if Settings.kooragang.read_only_database_url
    end
  end
end