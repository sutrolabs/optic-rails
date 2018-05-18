module Optic
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "optic_rails.launch_client_thread" do |app|
        api_key = app.config.optic_api_key # TODO fail gracefully if missing
        uri = app.config.optic_uri
        puts "Launching Optic client thread"
        Thread.new do

          EventMachine.run do
            puts "connecting"
            client = ActionCableClient.new(uri, { channel: "MetricsChannel" }, true, { "Authorization" => "Bearer #{api_key}" })
            client.connected do
              puts "successfully connected"
            end

            client.errored { |msg| puts "ERROR: #{msg}" }

            # called whenever a message is received from the server
            client.received do |message|
              puts "MESSAGE: #{message}"
              command = message["message"]["command"]

              case command
              when "request_schema"
                puts "Schema requested!"
                client.perform "schema", message: Optic::Rails.get_entities
              when "request_metrics"
                puts "Metrics requested!"
                client.perform "metrics", message: Optic::Rails.get_metrics(message["message"]["pivot"])
              else
                puts "unknown command!"
              end
            end
          end
        end
      end
    end
  end
end
