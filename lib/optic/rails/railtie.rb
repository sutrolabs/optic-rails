require "action_cable_client"
require "eventmachine"
require "logger"

module Optic
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "optic_rails.launch_client_thread" do |app|
        # TODO allow log output customization and verbose option
        logger = Logger.new(STDOUT)
        logger.level = Logger::WARN

        # Get configuration
        if !app.config.respond_to? :optic_api_key
          logger.warn "No optic_api_key found in Rails configuration, Optic agent will not run"
          next
        end

        api_key = app.config.optic_api_key
        uri = app.config.optic_uri

        logger.debug "Starting supervisor thread"
        supervisor = Thread.new do
          loop do
            logger.debug "Starting worker thread"
            worker = Thread.new do
              EventMachine.run do
                client = ActionCableClient.new(uri, { channel: "MetricsChannel" }, true, { "Authorization" => "Bearer #{api_key}" })

                client.connected do
                  logger.debug "Optic agent connected"
                end

                client.disconnected do
                  logger.info "Optic agent disconnected, killing client thread"
                  EventMachine.stop
                end

                client.errored do |msg|
                  logger.warn "Optic agent error: #{msg}"
                  EventMachine.stop
                end

                client.subscribed do
                  logger.debug "Optic agent subscribed"
                end

                client.pinged do |msg|
                  logger.debug "Optic agent pinged: #{msg}"
                  client.perform "pong", message: {}
                end

                # called whenever a message is received from the server
                client.received do |message|
                  logger.debug "Optic agent received: #{message}"
                  command = message["message"]["command"]

                  case command
                  when "request_schema"
                    logger.debug "Optic agent got schema request"
                    client.perform "schema", message: Optic::Rails.get_entities
                    logger.debug "Optic agent sent schema"
                  when "request_metrics"
                    logger.debug "Optic agent got metrics request"
                    client.perform "metrics", message: Optic::Rails.get_metrics(message["message"]["pivot"])
                    logger.debug "Optic agent sent metrics"
                  else
                    logger.warn "Optic agent got unknown command: #{command}"
                  end
                end
              end

              logger.info "Stopping worker thread"
            end

            begin
              worker.join
            rescue => e
              logger.error "Worker thread died with error: #{e}"
            end

            logger.info "Supervisor thread detected dead worker, sleeping"
            sleep 5.0
            logger.debug "Supervisor thread done sleeping"
          end
        end
      end
    end
  end
end
