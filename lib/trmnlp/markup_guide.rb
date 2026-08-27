# frozen_string_literal: true

module TRMNLP
  # The TRMNL template guide from usetrmnl/trmnl-agent-skills (MIT), sliced by
  # heading so an agent can ask for the one part it needs rather than reading
  # a hundred kilobytes to write six lines of Liquid.
  #
  # The document is fetched when the image is built rather than committed, so
  # an absent file is an ordinary state and never an error.
  class MarkupGuide
    Section = Data.define(:title, :level, :body)

    HEADING = /\A(\#+)\s+(.+?)\s*\z/
    LEVELS = (2..3)

    def initialize(path)
      @path = Pathname.new(path)
    end

    def available? = path.exist?

    def sections = @sections ||= available? ? parse(path.readlines(chomp: true)) : []

    def titles = sections.map(&:title)

    def find(title) = sections.find { it.title.casecmp?(title.to_s) }

    private

    attr_reader :path

    def parse(lines)
      headings = lines.each_with_index.filter_map do |line, index|
        match = HEADING.match(line)
        next unless match && LEVELS.cover?(match[1].length)

        [index, match[1].length, match[2]]
      end

      headings.map.with_index { |heading, position| build_section(heading, headings[(position + 1)..], lines) }
    end

    # A section runs until the next heading that is not nested inside it, so a
    # parent carries its subsections and a sibling ends it.
    def build_section((index, level, title), remaining, lines)
      following = remaining.find { |_, other_level, _| other_level <= level }

      Section.new(title:, level:, body: lines[(index + 1)...(following&.first || lines.length)].join("\n").strip)
    end
  end
end
