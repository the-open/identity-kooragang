module IdentityKooragang
  module ReadWrite
    def self.included(mod)
      mod.establish_connection Settings.kooragang.database_url if Settings.kooragang.database_url
    end
  end
end