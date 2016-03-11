require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module connecting to Redis.
    module Connection
      def initialize(options={})
        create_command_methods!
        @host = options[:host]
        @port = options[:port]
        @db = (options[:db] || 0).to_i
        @password = options[:password]
        @auto_reconnect = options.fetch(:auto_reconnect, true)
        @reconnect_on_error = options.fetch(:reconnect_on_error, true)
        @error_callback = lambda do |error|
          raise(error)
        end
        @reconnect_callbacks = {
          :before => lambda{},
          :after  => lambda{}
        }
      end

      def on_error(&block)
        @error_callback = block
      end

      def before_reconnect(&block)
        @reconnect_callbacks[:before] = block
      end

      def after_reconnect(&block)
        @reconnect_callbacks[:after] = block
      end

      def error(klass, message)
        redis_error = klass.new(message)
        @error_callback.call(redis_error)
      end

      def connected?
        @connected || false
      end

      def reconnect!
        @reconnect_callbacks[:before].call unless @reconnecting
        @reconnecting = true
        EM.add_timer(1) do
          reconnect(@host, @port)
        end
      end

      def close
        @closing = true
        close_connection_after_writing
      end

      def unbind
        @deferred_status = nil
        @response_callbacks = []
        @multibulk_count = false
        if @closing
          @reconnecting = false
        elsif ((@connected || @reconnecting) && @auto_reconnect) || @reconnect_on_error
          reconnect!
        elsif @connected
          error(ConnectionError, "connection closed")
        else
          error(ConnectionError, "unable to connect to redis server")
        end
        @connected = false
      end

      def validate_connection!
        info do |redis_info|
          if redis_info[:redis_version] < "1.3.14"
            error(ConnectionError, "redis version must be >= 2.0 RC 1")
          end
        end
      end

      def connection_completed
        @connected = true
        auth_and_select_db(@password, @db)
        validate_connection!
        @reconnect_callbacks[:after].call if @reconnecting
        @reconnecting = false
        succeed
      end
    end
  end
end
