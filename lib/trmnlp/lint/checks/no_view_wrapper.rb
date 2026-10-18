# frozen_string_literal: true

require_relative '../check'

module TRMNLP
  module Lint
    module Checks
      class NoViewWrapper < Check
        MESSAGE = "The markup has its own 'view', but TRMNL already puts each view in one. " \
                  "In a mashup the second 'view' shrinks to a thin strip and the screen shows only the 'title_bar'. " \
                  "Remove it and start the markup at the 'layout'."
        LEARN_MORE = 'https://trmnl.com/framework/docs/view'

        def misplaced_elements
          @misplaced_elements ||= source.html_fragments.flat_map do |path, fragment|
            fragment.css('.view').map { [path, it] }
          end
        end

        private

        def pass? = misplaced_elements.empty?
      end
    end
  end
end
