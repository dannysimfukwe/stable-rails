# frozen_string_literal: true

module Stable
  module Validators
    class AppName
      VALID_PATTERN = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
      MAX_LENGTH = 63

      def self.call!(name)
        normalized = normalize(name)

        unless valid?(normalized)
          raise Thor::Error, <<~MSG
            Invalid app name: "#{name}"

            Use only:
              - lowercase letters (a-z)
              - numbers (0-9)
              - hyphens (-)

            Rules:
              - no spaces or underscores
              - cannot start or end with a hyphen
              - max #{MAX_LENGTH} characters

            Example:
              stable new my-app
          MSG
        end

        normalized
      end

      def self.normalize(name)
        name
          .downcase
          .strip
          .gsub(/\s+/, '-') # spaces → hyphens
          .gsub(/[^a-z0-9-]/, '') # drop invalid chars
          .gsub(/-+/, '-')        # collapse hyphens
          .gsub(/\A-|-+\z/, '')   # trim hyphens
      end

      def self.valid?(name)
        name.length <= MAX_LENGTH && VALID_PATTERN.match?(name)
      end
    end
  end
end
