# frozen_string_literal: true

module Stable
  module Services
    module Tunneling
      # Base manager
      class BaseProvider
        def expose(_port)
          raise NotImplementedError
        end
      end
    end
  end
end
