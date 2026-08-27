# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe TRMNLP::MarkupGuide do
  subject(:guide) { described_class.new(path) }

  let(:tmp_root) { Dir.mktmpdir }
  let(:path) { File.join(tmp_root, 'template_guide.md') }
  let(:document) do
    <<~MARKDOWN
      # TRMNL Liquid Template Builder

      Intro text.

      ## 1. LAYOUT SYSTEM

      Use the layout container.

      ### grid

      Grids take columns.

      ### flex

      Flex takes a direction.

      ## 2. TYPOGRAPHY

      Values are for numbers.
    MARKDOWN
  end

  before { File.write(path, document) }

  after { FileUtils.remove_entry(tmp_root) }

  describe '#available?' do
    it 'is true when the guide is present' do
      expect(guide).to be_available
    end

    it 'is false when the guide was never fetched' do
      expect(described_class.new(File.join(tmp_root, 'absent.md'))).not_to be_available
    end
  end

  describe '#titles' do
    it 'lists every heading at both levels' do
      expect(guide.titles).to eq(['1. LAYOUT SYSTEM', 'grid', 'flex', '2. TYPOGRAPHY'])
    end

    it 'is empty when the guide was never fetched' do
      expect(described_class.new(File.join(tmp_root, 'absent.md')).titles).to be_empty
    end
  end

  describe '#find' do
    it 'returns a section body without its own heading' do
      expect(guide.find('2. TYPOGRAPHY').body).to eq('Values are for numbers.')
    end

    it 'stops a section at the next heading of the same level' do
      expect(guide.find('grid').body).to eq('Grids take columns.')
    end

    it 'includes nested subsections in their parent' do
      expect(guide.find('1. LAYOUT SYSTEM').body).to include('grid', 'Flex takes a direction')
    end

    it 'matches a title regardless of case' do
      expect(guide.find('2. typography')).not_to be_nil
    end

    it 'returns nil for a heading that does not exist' do
      expect(guide.find('nope')).to be_nil
    end
  end
end
