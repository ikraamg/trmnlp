# frozen_string_literal: true

require 'spec_helper'
require 'trmnlp/lint/source'
require 'trmnlp/lint/checks/no_view_wrapper'

RSpec.describe TRMNLP::Lint::Checks::NoViewWrapper do
  subject(:check) { described_class.new(source) }

  let(:source) { instance_double(TRMNLP::Lint::Source, html_fragments: { 'src/half_vertical.liquid' => Nokogiri::HTML.fragment(markup) }) }

  describe '#issues' do
    context 'when the markup has its own view' do
      let(:markup) { '<div class="view"><div class="layout">x</div><div class="title_bar">t</div></div>' }

      it 'reports the issue' do
        expect(check.issues).not_to be_empty
      end
    end

    context 'when the view names its size' do
      let(:markup) { '<div class="view view--half_vertical"><div class="layout">x</div></div>' }

      it 'reports the issue' do
        expect(check.issues).not_to be_empty
      end
    end

    context 'when the markup starts at the layout' do
      let(:markup) { '<div class="layout"><span class="view--count">x</span></div><div class="title_bar">t</div>' }

      it 'passes' do
        expect(check.issues).to be_empty
      end
    end
  end
end
