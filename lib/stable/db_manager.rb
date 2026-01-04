# frozen_string_literal: true

module Stable
  class DBManager
    attr_reader :name, :adapter

    def initialize(name, adapter:)
      @name = name
      @adapter = adapter
    end

    # Main entry
    def create
      case adapter
      when :postgresql
        ensure_postgres_database
      when :mysql
        ensure_mysql_database
      else
        abort "Unsupported database adapter: #{adapter}"
      end
    end

    # Rails database.yml config
    def rails_config
      case adapter
      when :postgresql
        {
          'adapter' => 'postgresql',
          'encoding' => 'unicode',
          'database' => name,
          'username' => app_user,
          'password' => nil,
          'host' => 'localhost',
          'pool' => 5
        }
      when :mysql
        {
          'adapter' => 'mysql2',
          'encoding' => 'utf8mb4',
          'database' => name,
          'username' => app_user,
          'password' => '',
          'host' => 'localhost',
          'socket' => mysql_socket,
          'pool' => 5
        }
      else
        abort "Unsupported adapter for Rails config: #{adapter}"
      end
    end

    private

    # -------------------- PostgreSQL --------------------

    def ensure_postgres_database
      exists = system(%(psql -lqt | cut -d \\| -f 1 | grep -w #{name} >/dev/null))

      if exists
        puts "⚠ Postgres database '#{name}' already exists. Skipping creation."
      else
        system("createdb #{name}") or abort("Failed to create Postgres DB '#{name}'")
      end
    end

    # -------------------- MySQL --------------------

    def ensure_mysql_database
      ensure_mysql_root_auth!

      # Create DB and user
      socket = mysql_socket
      user = app_user

      system(%(
        mysql --protocol=SOCKET --socket=#{socket} -u root <<SQL
          CREATE DATABASE IF NOT EXISTS #{name};
          CREATE USER IF NOT EXISTS '#{user}'@'localhost' IDENTIFIED BY '';
          GRANT ALL PRIVILEGES ON #{name}.* TO '#{user}'@'localhost';
          FLUSH PRIVILEGES;
        SQL
      )) or abort("Failed to create MySQL DB '#{name}'")

      puts "✅ MySQL database '#{name}' ready"
    end

    # Ensure root can connect via socket
    def ensure_mysql_root_auth!
      ok = system("mysql -u root -e 'SELECT 1' >/dev/null 2>&1")
      return if ok

      puts '⚠ Fixing MySQL root authentication (requires sudo)...'
      socket = mysql_socket

      system(%(
        sudo mysql --protocol=SOCKET --socket=#{socket} <<SQL
          ALTER USER 'root'@'localhost' IDENTIFIED BY '';
          FLUSH PRIVILEGES;
        SQL
      )) or abort('Failed to repair MySQL root authentication')
    end

    # Detect MySQL socket on macOS / Linux / Windows
    def mysql_socket
      platform = RUBY_PLATFORM

      paths = case platform
              when /darwin/ # macOS
                [
                  '/opt/homebrew/var/mysql/mysql.sock', # Homebrew macOS
                  '/tmp/mysql.sock'                     # Fallback
                ]
              when /linux/
                [
                  '/var/run/mysqld/mysqld.sock', # Linux default
                  '/tmp/mysql.sock' # Fallback
                ]
              when /mingw|mswin|win32/ # Windows
                # Windows typically uses TCP connections, not sockets
                return nil
              else
                ['/tmp/mysql.sock'] # Generic fallback
              end

      paths.each { |p| return p if File.exist?(p) }
      abort 'MySQL socket not found. Is MySQL running? (On Windows, ensure MySQL is configured for TCP connections)'
    end

    # Default Rails DB user
    def app_user
      ENV['USER'] || 'stable'
    end
  end
end
