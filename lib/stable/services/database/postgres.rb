# frozen_string_literal: true

module Stable
  module Services
    module Database
      # PostgreSQL database management service
      class Postgres < Base
        def setup
          System::Shell.run("createdb #{@database_name}")
          prepare
        end
      end
    end
  end
end
