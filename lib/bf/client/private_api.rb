module BF
  class Client
    class BaseRequest
      def  initialize(path: nil)
        path =
          if defined?(Rails)
            File.join(Rails.root, 'bf_config.yaml')
          else
            'bf_config.yaml'
          end
        @config =
          if ENV['RUN_ENV'] == 'test'
            {"api_key" => "2", "api_secret" => "N"}
          else
            YAML.load(File.open(path))
          end
      end

      def api_key
        @config['api_key']
      end

      def api_secret
        @config['api_secret']
      end

      def timestamp
        @timestamp ||= Time.current.to_i.to_s
      end

      def uri
        @uri ||= URI.parse(END_POINT)
      end

      def run(path: , http_class: , query: nil, timeout: 120)
        http_method =
          case
          when http_class == Net::HTTP::Post
            :POST
          when http_class == Net::HTTP::Get
            :GET
          else
            raise 'unknown http class'
          end
        default_body = {
          product_code: BTC_FX_PRODUCT_CODE,
          child_order_type: 'LIMIT',
        }
        body = yield(default_body) if block_given?
        uri.path = path
        uri.query = query if query
        text = [timestamp, http_method, uri.request_uri, body].join
        sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), api_secret, text)
        options = http_class.new(uri.request_uri, initheader = {
          "ACCESS-KEY" => api_key,
          "ACCESS-TIMESTAMP" => timestamp,
          "ACCESS-SIGN" => sign,
          "Content-Type" => "application/json",
        })
        options.body = body if block_given?
        https = Net::HTTP.new(uri.host, uri.port)
        https.read_timeout = https.open_timeout = https.ssl_timeout = timeout
        https.use_ssl = true
        response = https.request(options)
        BF.logger.info "#{http_method}: #{uri.request_uri}?#{body}, response_body: #{response.body.presence || []}, response_code: #{response.code}"
        if response.body.empty?
          return response.code
        else
          res = JSON.parse(response.body)
          BF::ApiCallLog.create!(api_type: :private_api,
                                 request_body: "#{uri.request_uri}?#{body && body[0..100]}",
                                 response_code: response.code,
                                 response_body: response.body && response.body[0..100])
          if res.is_a?(Array) # for get order
            return res
          end
          if res['child_order_acceptance_id'] # for new order
            return res['child_order_acceptance_id']
          end
          if res['error_message'] # for new order
            raise(res['error_message'])
          end
        end
      rescue => e
        BF::ApiCallLog.create!(api_type: :private_api,
                               request_body: "#{http_method}: #{uri.request_uri}?",
                               error_trace:  [e.inspect + e.full_message].join("\n"),
                               response_code: response&.code,
                               response_body: (response&.body && response.body[0..100]))
        raise
      end
    end

    class BuyRequest < BaseRequest
      def run(price, size)
        super(path: '/v1/me/sendchildorder', http_class: Net::HTTP::Post) do |body|
          body.merge(price: price, size: size, side: 'BUY').to_json
        end
      end
    end

    class SellRequest < BaseRequest
      def run(price, size)
        super(path: '/v1/me/sendchildorder', http_class: Net::HTTP::Post) do |body|
          body.merge(price: price, size: size, side: 'SELL').to_json
        end
      end
    end

    class CancelRequest < BaseRequest
      def run(order_acceptance_id)
        super(path: '/v1/me/cancelchildorder', http_class: Net::HTTP::Post, timeout: 10) do |body|
          body.merge({ child_order_acceptance_id: order_acceptance_id }).to_json
        end
      end
    end

    class GetPreorderListRequest < BaseRequest
      def run
        query = [
          "product_code=#{BTC_FX_PRODUCT_CODE}",
          "child_order_state=ACTIVE",
        ].join('&')
        response = super(path: '/v1/me/getchildorders',
                         http_class: Net::HTTP::Get,
                         query: query,
                         timeout: 2)
        response.map do |preorder|
          preorder.slice('child_order_acceptance_id', 'side', 'price', 'size')
        end
      end
    end

    class GetOrderRequest < BaseRequest
      def run(order_acceptance_id: )
        order_query = "child_order_acceptance_id=#{order_acceptance_id}"
        response = super(path: "/v1/me/getexecutions",
                         http_class: Net::HTTP::Get,
                         query: "product_code=#{BTC_FX_PRODUCT_CODE}&#{order_query}",
                         timeout: 2)
        response.map do |order|
          order.slice('child_order_id', 'child_order_acceptance_id', 'exec_date', 'id', 'price', 'size')
        end
      end
    end


    class GetRegistratedOrders < BaseRequest
      def run(before_processing: false)
        response = super(path: "/v1/me/getchildorders",
                         http_class: Net::HTTP::Get,
                         query: "product_code=#{BTC_FX_PRODUCT_CODE}&child_order_state=ACTIVE",
                         timeout: 10)
        if before_processing
          response
        else
          response.map do |hash|
            { size: hash['size'],
              price: hash['price'],
              kind: hash['side'].downcase,
            }
          end
        end
      end
    end
  end
end
