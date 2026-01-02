# frozen_string_literal: true

module Stable
  module Services
    module Database
      class Base
        def initialize(app_name:, app_path:)
          @app_name = app_name
          @app_path = app_path
        end

        def prepare
          System::Shell.run(
            "cd #{@app_path} && bundle exec rails db:prepare"
          )
        end

        protected

        def write_database_yml(creds)
          config = {
            'default' => base_config(creds),
            'development' => base_config(creds),
            'test' => base_config(creds).merge(
              'database' => "#{@app_name}_test"
            ),
            'production' => base_config(creds).merge(
              'database' => "#{@app_name}_production"
            )
          }

          path = File.join(@app_path, 'config/database.yml')
          File.write(path, config.to_yaml)
        end

        def base_config(_creds)
          raise NotImplementedError
        end
      end
    end
  end
end
