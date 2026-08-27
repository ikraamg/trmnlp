# frozen_string_literal: true

require_relative 'errors'
require_relative 'screen'

module TRMNLP
  # Read and write a plugin's Liquid templates over HTTP. Split out of App so
  # the surface an agent talks to stays small enough to read in one sitting.
  module MarkupAPI
    # A view name reaches us from an agent, so this is an allow-list check and
    # not a path sanitize: paths.template would resolve `../../` without complaint.
    EDITABLE_VIEWS = (Screen.names + ['shared']).freeze

    module Helpers
      def validate_view!(view)
        raise InvalidView, "view must be one of: #{EDITABLE_VIEWS.join(', ')}" unless EDITABLE_VIEWS.include?(view)

        view
      end

      def read_markup(name)
        view = validate_view!(name)
        template = @context.paths.template(view)

        { view:, markup: template.exist? ? template.read : '' }
      end

      # The watcher sees the write and live-reloads the preview, so there is
      # nothing to re-render here.
      def write_markup(payload)
        view = validate_view!(payload['view'])
        markup = payload['markup']
        raise InvalidView, 'markup must be a string' unless markup.is_a?(String)

        template = @context.paths.template(view)
        remember_original(template)
        template.dirname.mkpath
        template.write(markup)

        { success: true, view:, bytes: markup.bytesize }
      end

      def reset_markup
        restored = @context.markup_originals.map do |path, original|
          template = Pathname.new(path)
          original.nil? ? template.delete : template.write(original)
          template.basename('.liquid').to_s
        end
        @context.markup_originals.clear

        { success: true, restored: }
      end

      def json_response
        content_type :json
        yield.to_json
      rescue InvalidRequest => e
        status 400
        { error: e.message }.to_json
      rescue StandardError => e
        status 500
        { error: e.message }.to_json
      end

      private

      def remember_original(template)
        originals = @context.markup_originals
        return if originals.key?(template.to_s)

        originals[template.to_s] = template.exist? ? template.read : nil
      end
    end

    def self.registered(app)
      app.helpers Helpers

      app.get('/api/markup') { json_response { read_markup(params[:view] || Screen::FULL.name) } }
      app.post('/api/markup') { json_response { write_markup(parse_json_object(request.body.read)) } }
      app.post('/api/markup/reset') { json_response { reset_markup } }
    end
  end
end
