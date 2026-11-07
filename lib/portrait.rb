# frozen_string_literal: true

require "zlib"

# Draws every reviewed pull request as one dot, like the rings of a tree: dots
# follow a golden-angle spiral outwards from the oldest review, with a thin gap
# between years.
module Portrait
  SIZE = 1200
  DISPLAY_SIZE = 600
  HOLE_RADIUS = 186.0
  OUTER_RADIUS = 592.0
  DOT_RADIUS = 1.55
  GOLDEN_ANGLE = Math::PI * (3 - Math.sqrt(5))
  YEAR_GAP_IN_DOTS = 800
  COLOUR_LEVELS = 40
  COVERAGE_LEVELS = 5
  FONT_STACK = %(-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif)

  def self.dots(yearly_counts)
    total = yearly_counts.sum
    gaps = YEAR_GAP_IN_DOTS * (yearly_counts.length - 1)
    area_per_dot = ((OUTER_RADIUS**2) - (HOLE_RADIUS**2)) / (total + gaps)
    centre = SIZE / 2.0
    position = 0
    dots = []
    yearly_counts.each do |count|
      count.times do
        radius = Math.sqrt((HOLE_RADIUS**2) + (area_per_dot * position))
        angle = position * GOLDEN_ANGLE
        dots << [centre + (radius * Math.cos(angle)), centre + (radius * Math.sin(angle)), dots.length.fdiv(total)]
        position += 1
      end
      position += YEAR_GAP_IN_DOTS
    end
    dots
  end

  def self.pixels(yearly_counts)
    pixels = Array.new(SIZE * SIZE, 0)
    reach = (DOT_RADIUS + 1).ceil
    dots(yearly_counts).each do |dot_x, dot_y, progress|
      colour_level = [(progress * COLOUR_LEVELS).floor, COLOUR_LEVELS - 1].min
      ((dot_y.floor - reach)..(dot_y.floor + reach)).each do |y|
        ((dot_x.floor - reach)..(dot_x.floor + reach)).each do |x|
          coverage = (DOT_RADIUS + 0.5 - Math.hypot(x + 0.5 - dot_x, y + 0.5 - dot_y)).clamp(0.0, 1.0)
          coverage_level = (coverage * COVERAGE_LEVELS).ceil
          next if coverage_level.zero?

          offset = (y * SIZE) + x
          pixels[offset] = [pixels[offset], (colour_level * COVERAGE_LEVELS) + coverage_level].max
        end
      end
    end
    pixels
  end

  def self.ramp(stops, progress)
    channels = stops.map { |hex| hex.delete("#").scan(/../).map { |pair| pair.to_i(16) } }
    position = progress * (channels.length - 1)
    lower = [position.floor, channels.length - 2].min
    channels[lower].zip(channels[lower + 1]).map do |from, to|
      (from + ((to - from) * (position - lower))).round
    end
  end

  def self.palette(stops)
    entries = [[0, 0, 0, 0]]
    COLOUR_LEVELS.times do |colour_level|
      colour = ramp(stops, colour_level.fdiv(COLOUR_LEVELS - 1))
      (1..COVERAGE_LEVELS).each do |coverage_level|
        entries << [*colour, (255 * coverage_level.fdiv(COVERAGE_LEVELS)).round]
      end
    end
    entries
  end

  def self.chunk(type, data)
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end

  def self.png(yearly_counts, stops)
    colours = palette(stops)
    rows = pixels(yearly_counts).each_slice(SIZE).map { |row| "\0".b + row.pack("C*") }.join
    [
      "\x89PNG\r\n\x1A\n".b,
      chunk("IHDR", [SIZE, SIZE, 8, 3, 0, 0, 0].pack("NNCCCCC")),
      chunk("PLTE", colours.flat_map { |colour| colour.first(3) }.pack("C*")),
      chunk("tRNS", colours.map(&:last).pack("C*")),
      chunk("IDAT", Zlib.deflate(rows, Zlib::BEST_COMPRESSION)),
      chunk("IEND", "".b),
    ].join
  end

  def self.animation
    <<~CSS.delete("\n")
      @keyframes grow{from{clip-path:circle(16% at 50% 50%)}to{clip-path:circle(50% at 50% 50%)}}
      @keyframes appear{from{opacity:0}}
      .rings{animation:grow 2.6s cubic-bezier(.2,.6,.1,1) both}
      .number,.label{animation:appear .8s ease-out both}
    CSS
  end

  def self.svg(yearly_counts, number, theme, animated:)
    centre = DISPLAY_SIZE / 2
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{DISPLAY_SIZE} #{DISPLAY_SIZE}" width="#{DISPLAY_SIZE}" height="#{DISPLAY_SIZE}" role="img">
      <title>#{number} pull requests reviewed</title>
      <style>text{font-family:#{FONT_STACK};text-anchor:middle}.number{font-size:46px;font-weight:600;letter-spacing:-.02em;fill:#{theme.fetch(:ink)}}.label{font-size:15px;fill:#{theme.fetch(:ink_muted)}}#{animation if animated}</style>
      <image class="rings" width="#{DISPLAY_SIZE}" height="#{DISPLAY_SIZE}" href="data:image/png;base64,#{[png(yearly_counts, theme.fetch(:rings))].pack("m0")}"/>
      <text class="number" x="#{centre}" y="#{centre + 8}">#{number}</text>
      <text class="label" x="#{centre}" y="#{centre + 32}">reviews</text>
      </svg>
    SVG
  end
end
