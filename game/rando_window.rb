# The game window can be dragged bigger from its edges and corners, and F6 steps through set sizes
# It stays 4:3 and the size is remembered, a problem here turns this off and the game carries on

module RandoWindow
  FILE = Rando::DIR + "/window.txt"
  SHARP_DLL = Rando::DIR + "\\rando_sharp.dll"
  KEY = :F6
  BASE_WIDTH = 640
  BASE_HEIGHT = 480
  MIN_WIDTH = 320
  SCALES = [1.0, 1.5, 2.0, 3.0, 4.0]
  # a drag that ends this close to a whole multiple lands on it, whole multiples look sharpest
  SNAP = 32
  POLL_FRAMES = 15
  GWL_STYLE = -16
  WS_CAPTION = 0x00C00000
  WS_THICKFRAME = 0x00040000
  SPI_GETWORKAREA = 48
  VK_LBUTTON = 1
  SWP_NOSIZE = 0x0001
  SWP_NOMOVE = 0x0002
  SWP_NOZORDER = 0x0004
  SWP_NOACTIVATE = 0x0010
  SWP_FRAMECHANGED = 0x0020

  @width = nil
  @last = nil
  @started = false
  @dead = false
  @frames = 0

  def self.api(name, spec, result = "L")
    @api ||= {}
    @api[name] ||= Win32API.new("user32", name, spec, result)
  end

  def self.handle
    @handle ||= api("FindWindowA", "PP").call("RGSS Player", nil)
  end

  def self.style
    api("GetWindowLongA", "LL").call(handle, GWL_STYLE)
  end

  # exclusive fullscreen has no title bar, the engine owns the size then
  def self.windowed?
    handle != 0 && style & WS_CAPTION != 0
  end

  def self.client
    rect = "\0" * 16
    api("GetClientRect", "LP").call(handle, rect)
    values = rect.unpack("l4")
    [values[2] - values[0], values[3] - values[1]]
  end

  def self.outer_size(width, height)
    rect = [0, 0, width, height].pack("l4")
    api("AdjustWindowRect", "PLL").call(rect, style, 0)
    values = rect.unpack("l4")
    [values[2] - values[0], values[3] - values[1]]
  end

  def self.work_area
    area = "\0" * 16
    api("SystemParametersInfoA", "LLPL").call(SPI_GETWORKAREA, 0, area, 0)
    area.unpack("l4")
  end

  def self.height_for(width)
    width * BASE_HEIGHT / BASE_WIDTH
  end

  def self.largest_width
    left, top, right, bottom = work_area
    frame = outer_size(0, 0)
    room_w = right - left - frame[0]
    room_h = bottom - top - frame[1]
    [room_w, room_h * BASE_WIDTH / BASE_HEIGHT].min
  end

  def self.preset_widths
    top = largest_width
    list = SCALES.map { |s| (BASE_WIDTH * s).to_i }.select { |w| w <= top }
    list.empty? ? [BASE_WIDTH] : list
  end

  def self.place(width, flags, x = 0, y = 0)
    outer = outer_size(width, height_for(width))
    api("SetWindowPos", "LLLLLLL").call(handle, 0, x, y, outer[0], outer[1], flags | SWP_NOZORDER | SWP_NOACTIVATE)
    @width = width
    @last = [width, height_for(width)]
  end

  def self.place_centered(width)
    outer = outer_size(width, height_for(width))
    left, top, right, bottom = work_area
    place(width, 0, left + (right - left - outer[0]) / 2, top + (bottom - top - outer[1]) / 2)
  end

  # the engine makes a fixed border, this turns on the one you can drag
  def self.allow_dragging
    current = style
    return if current & WS_THICKFRAME != 0
    api("SetWindowLongA", "LLL").call(handle, GWL_STYLE, current | WS_THICKFRAME)
    api("SetWindowPos", "LLLLLLL").call(handle, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)
    # the thicker border took some room from the picture
    place(@width || BASE_WIDTH, SWP_NOMOVE) if @started
  end

  def self.snapped(width)
    multiple = (width.to_f / BASE_WIDTH).round * BASE_WIDTH
    multiple > 0 && (width - multiple).abs <= SNAP ? multiple : width
  end

  # waits for the mouse button so it never fights you in the middle of a drag
  def self.poll
    return unless windowed?
    allow_dragging
    now = client
    @last ||= now
    return if now == @last || now[0] <= 0 || now[1] <= 0
    return if api("GetAsyncKeyState", "L").call(VK_LBUTTON) & 0x8000 != 0
    moved_w = (now[0] - @last[0]).abs
    moved_h = (now[1] - @last[1]).abs
    width = moved_w >= moved_h ? now[0] : now[1] * BASE_WIDTH / BASE_HEIGHT
    width = [[snapped(width), MIN_WIDTH].max, largest_width].min
    return @last = now if now == [width, height_for(width)]
    place(width, SWP_NOMOVE)
    save
  end

  def self.step
    return unless windowed?
    allow_dragging
    list = preset_widths
    current = @width || client[0]
    place_centered(list.find { |w| w > current } || list[0])
    save
  end

  def self.save
    Dir.mkdir(Rando::DIR) unless File.directory?(Rando::DIR)
    File.open(FILE, "wb") { |f| f.write(@width.to_s) }
  rescue SystemCallError, IOError
    nil
  end

  # the first version of this file held a multiplier like 2.0
  def self.saved_width
    return nil unless File.exist?(FILE)
    value = File.read(FILE).to_f
    return nil if value <= 0
    value < 16 ? (BASE_WIDTH * value).to_i : value.to_i
  rescue SystemCallError, IOError
    nil
  end

  # the dll takes over the stretch that makes a bigger window blurry
  def self.load_sharp
    return unless File.exist?(SHARP_DLL)
    @sharp ||= Win32API.new(SHARP_DLL, "RandoSharpInstall", "", "L")
    @sharp.call
  rescue StandardError, LoadError
    nil
  end

  def self.restore
    @started = true
    load_sharp
    return unless windowed?
    want = saved_width || BASE_WIDTH
    @width = [[want, MIN_WIDTH].max, largest_width].min
    @last = nil
    allow_dragging
    place_centered(@width)
  end

  def self.tick
    return if @dead
    restore unless @started
    step if Input.trigger?(KEY)
    @frames += 1
    return if @frames < POLL_FRAMES
    @frames = 0
    poll
  rescue StandardError
    @dead = true
  end
end

class Scene_Base
  alias window_update_basic update_basic
  def update_basic
    window_update_basic
    RandoWindow.tick
  end
end
