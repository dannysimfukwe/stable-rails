# frozen_string_literal: true

module Stable
  module Services
    module Database
      class Postgres < Base
        def setup
          System::Shell.run("createdb #{@app_name}")
          prepare
        end
      end
    end
  end
end
