# frozen_string_literal: true

module Stable
  module Services
    module Database
      class MySQL < Base
        def setup
          creds = Stable::Utils::Prompts.mysql_root_credentials
          create_database(creds)
          write_database_yml(creds)
          prepare
        end

        def create_database(creds)
          System::Shell.run(
            "mysql -u #{creds[:user]} -p#{creds[:password]} -e 'CREATE DATABASE IF NOT EXISTS #{@app_name};'"
          )
        end

        protected

        def base_config(creds)
          {
            'adapter' => 'mysql2',
            'encoding' => 'utf8mb4',
            'pool' => 5,
            'database' => @app_name,
            'username' => creds[:user],
            'password' => creds[:password],
            'host' => 'localhost'
          }
        end
      end
    end
  end
end
