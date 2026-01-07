# frozen_string_literal: true

require 'rqrcode'

module Stable
  module Services
    module Cli
      # Generate QR code
      class QrCode
        def self.print(url)
          qr = RQRCode::QRCode.new(url)

          puts
          qr.modules.each do |row|
            puts row.map { |cell| cell ? '██' : '  ' }.join
          end
          puts
        end
      end
    end
  end
end
