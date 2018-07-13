# frozen_string_literal: true

require "action_cable_client"
require "eventmachine"
require "logger"

module Optic
  module Rails
    class Railtie < ::Rails::Railtie
      config.optic = ActiveSupport::OrderedOptions.new

      initializer "optic_rails.launch_client_thread" do |app|
        logger = Logger.new(STDOUT)
        logger.level = config.optic.debug ? Logger::DEBUG : Logger::WARN

        did_print_project_key_warning = false

        logger.debug "Starting supervisor thread"
        supervisor = Thread.new do
          loop do
            sleep 5.0

            # Get configuration
            if !config.optic.project_key
              logger.warn "No optic.project_key found in Rails configuration, Optic agent will not run" unless did_print_project_key_warning
              did_print_project_key_warning = true
              next
            end

            project_key = config.optic.project_key
            uri = config.optic.uri || "wss://sutrolabs-tikal-api-production.herokuapp.com/cable"

            logger.debug "Starting worker thread"
            worker = Thread.new do
              EventMachine.run do
                client = ActionCableClient.new(uri, { channel: "MetricsChannel" }, true, "Authorization" => "Bearer #{project_key}")

                client.connected do
                  logger.debug "Optic agent connected"
                end

                client.disconnected do
                  logger.info "Optic agent disconnected, killing client thread"
                  EventMachine.stop
                end

                client.errored do |data|
                  logger.warn "Optic agent error: #{data}"
                  EventMachine.stop
                end

                client.subscribed do
                  logger.debug "Optic agent subscribed"
                end

                client.pinged do |data|
                  logger.debug "Optic agent pinged: #{data}"
                  client.perform "pong", message: {}
                end

                # called whenever a message is received from the server
                client.received do |data|
                  logger.debug "Optic agent received: #{data}"
                  message = data["message"]
                  command = message["command"]

                  case command
                  when "request_schema"
                    client.perform "schema", message: Optic::Rails.entities(logger)
                  when "request_metrics"
                    client.perform "metrics", message: Optic::Rails.metrics(logger, message["instructions"])
                  else
                    logger.warn "Optic agent got unknown command: #{command}"
                  end

                  logger.debug "Optic agent completed command: #{command}"
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
          end
        end
      end
    end
  end
end
