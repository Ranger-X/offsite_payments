module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Uniteller
      # Overwrite this if you want to change the Uniteller test url
      mattr_accessor :test_url
      self.test_url = 'https://test.wpay.uniteller.ru/pay/'

      # Overwrite this if you want to change the Uniteller production url
      mattr_accessor :production_url
      self.production_url = 'https://wpay.uniteller.ru/pay/'

      mattr_accessor :signature_parameter_name
      self.signature_parameter_name = 'Signature'

      def self.service_url
        mode = OffsitePayments.mode
        mode = :test
        url = case mode
                when :production
                  self.production_url
                when :test
                  self.test_url
                else
                  raise StandardError, "Integration mode set to an invalid value: #{mode}"
              end

        Rails.logger.warn "Uniteller URL: #{url} for mode #{mode}"
        url
      end

      def self.helper(order, account, options = {})
        Helper.new(order, account, options)
      end

      def self.notification(query_string, options = {})
        Notification.new(query_string, options)
      end

      def self.return(query_string)
        Return.new(query_string)
      end

      module Common
        def generate_signature_string
          #custom_param_keys = params.keys.select {|key| key =~ /^shp/}.sort
          #custom_params = custom_param_keys.map {|key| "#{key}=#{params[key]}"}
          [main_params, optional_params, secret].flatten.map { |val| Digest::MD5.hexdigest(val.to_s) }.join('&')
        end

        def generate_signature
=begin
          Signature = uppercase(md5(md5(Shop_IDP) + '&' +
                                        md5(Order_IDP) + '&' + md5(Subtotal_P) + '&' + md5(MeanType) +
                                        '&' + md5(EMoneyType) + '&' + md5(Lifetime) + '&' +
                                        md5(Customer_IDP) + '&' + md5(Card_IDP) + '&' + md5(IData) +
                                        '&' + md5(PT_Code) + '&' + md5(password)))
=end
          Digest::MD5.hexdigest(generate_signature_string).upcase
        end
      end

      class Helper < OffsitePayments::Helper
        include Common

        def initialize(order, account, options = {})
          @md5secret = options.delete(:secret)

          super

          add_field('CallbackFields', 'Total') # want Total summ in callback
        end

        def form_fields
          @fields.merge(OffsitePayments::Integrations::Uniteller.signature_parameter_name => generate_signature)
        end

        def main_params
          [:account, :order, :amount].map { |key| @fields[mappings[key]] }
        end

        def optional_params
          # 'string' literals in below array just skipped in signature string (assigning value of empty string)
          [:credential2, :currency, 'lifetime', 'customer_IDP', 'card_idp', 'idata', 'pt_code'].map { |key| key.is_a?(String) ? '' : @fields[mappings[key]] }
        end

        def params
          @fields
        end

        def secret
          @md5secret
        end

        mapping :account, 'Shop_IDP'
        mapping :amount, 'Subtotal_P'
        mapping :currency, 'EMoneyType'
        mapping :order, 'Order_IDP'
        mapping :credential2, 'MeanType'
        mapping :credential3, 'Email'
        mapping :return_url, 'URL_RETURN_OK'
        mapping :notify_url, 'URL_RETURN_NO'
      end

      class Notification < OffsitePayments::Notification
        include Common

        def self.recognizes?(params)
          params.has_key?('Order_ID') && params.has_key?('Status')
        end

        def complete?
          status == 'Completed'
        end

        def amount
          BigDecimal.new(gross)
        end

        def gross
          params['Total']
        end

        def item_id
          params['Order_ID']
        end

        def my_status
          params['Status'].to_s.downcase
        end

        def security_key
          params[OffsitePayments::Integrations::Uniteller.signature_parameter_name].to_s
        end

        def status
          case my_status
            when 'authorized', 'paid'
              'Completed'
            when 'waiting'
              'Pending'
            when 'canceled'
              'Cancelled'
            else
              'Failed'
          end
        end

        def secret
          @options[:secret]
        end

        def acknowledge(authcode = nil)
          security_key == Digest::MD5.hexdigest("#{item_id}#{my_status}#{gross}#{secret}").upcase
        end

        def test?
          OffsitePayments.mode == :test
        end
      end

      class Return < OffsitePayments::Return
      end
    end
  end
end
