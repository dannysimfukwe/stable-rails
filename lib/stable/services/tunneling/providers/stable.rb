# frozen_string_literal: true

module Stable
  module Services
    module Tunneling
      module Providers
        # stable provider
        class Stable
          # skip_ssl is kept for future use
          def expose(*)
            abort 'Stable tunnels are not available yet'
          end
        end
      end
    end
  end
end
