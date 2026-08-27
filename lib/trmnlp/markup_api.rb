# frozen_string_literal: true

require_relative 'errors'
require_relative 'screen'

module TRMNLP
  # Read and write a plugin's Liquid templates over HTTP. Split out of App so
  # the surface an agent talks to stays small enough to read in one sitting.
  module MarkupAPI
    # A view name reaches us from an agent, so this is an allow-list check and
    # not a path sanitize — paths.template would resolve `../../` without complaint.
    EDITABLE_VIEWS = (Screen.names + ['shared']).freeze

    module Helpers
      def validate_view!(view)
        raise InvalidView, "view must be one of: #{EDITABLE_VIEWS.join(', ')}" unless EDITABLE_VIEWS.include?(view)

        view
      end
    end

    def self.registered(app)
      app.helpers Helpers

      app.get '/api/markup' do
        content_type :json

        view = validate_view!(params[:view] || Screen::FULL.name)
        template = @context.paths.template(view)

        { view:, markup: template.exist? ? template.read : '' }.to_json
      rescue InvalidRequest => e
        status 400
        { error: e.message }.to_json
      end

      # The watcher sees the write and live-reloads the preview, so there is
      # nothing to re-render here.
      app.post '/api/markup' do
        content_type :json

        payload = parse_json_object(request.body.read)
        view = validate_view!(payload['view'])
        markup = payload['markup']
        raise InvalidView, 'markup must be a string' unless markup.is_a?(String)

        template = @context.paths.template(view)
        template.dirname.mkpath
        template.write(markup)

        { success: true, view:, bytes: markup.bytesize }.to_json
      rescue InvalidRequest => e
        status 400
        { error: e.message }.to_json
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end
    end
  end
end
