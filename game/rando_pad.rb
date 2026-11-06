# Reads Xbox style controllers through XInput, the engine only sees one old joystick device
module RandoPad
  DPAD_UP = 0x0001
  DPAD_DOWN = 0x0002
  DPAD_LEFT = 0x0004
  DPAD_RIGHT = 0x0008
  START = 0x0010
  BACK = 0x0020
  LB = 0x0100
  RB = 0x0200
  PAD_A = 0x1000
  PAD_B = 0x2000
  PAD_X = 0x4000
  PAD_Y = 0x8000
  ACTIONS = { PAD_A => :C, PAD_B => :B, PAD_X => :A, PAD_Y => :Z, LB => :L, RB => :R, START => :B }
  # the order the engine numbers the same buttons in
  ENGINE_ORDER = [PAD_A, PAD_B, PAD_X, PAD_Y, LB, RB, BACK, START]
  ENGINE_CODES = { 11 => :A, 12 => :B, 13 => :C, 14 => :X, 15 => :Y, 16 => :Z, 17 => :L, 18 => :R }
  DEFAULT_ASSIGN = [11, 13, 12, 14, 17, 18, 17, 12]
  KEY_CODES = { 2 => :DOWN, 4 => :LEFT, 6 => :RIGHT, 8 => :UP }.merge(ENGINE_CODES)
  DLLS = ["xinput1_4", "xinput1_3", "xinput9_1_0"]
  STICK_ON = 12000
  STICK_OFF = 8000
  TRIGGER_ON = 100
  SCAN_EVERY = 180
  GHOST_FRAMES = 2
  REPEAT_START = 24
  REPEAT_EVERY = 6
  ERROR_NOT_CONNECTED = 1167
  HKEY_CURRENT_USER = 0x80000001
  KEY_READ = 0x20019

  @held = {}
  @ghost = {}
  @slots = []
  @scan = 0
  @stick = {}

  def self.reset
    @held = {}
    @ghost = {}
    @slots = []
    @scan = 0
    @stick = {}
    @get_state = nil
    @engine_map = nil
    @broken = false
    @foreground = nil
  end

  def self.get_state
    return @get_state if @get_state
    DLLS.each do |dll|
      begin
        @get_state = Win32API.new(dll, "XInputGetState", "LP", "L")
        return @get_state
      rescue StandardError
        next
      end
    end
    nil
  end

  # which logical key the engine reports for each physical button
  def self.engine_map
    return @engine_map if @engine_map
    assign = read_assign || DEFAULT_ASSIGN
    @engine_map = {}
    ENGINE_ORDER.each_with_index do |bit, i|
      name = ENGINE_CODES[assign[i]]
      @engine_map[bit] = name if name
    end
    @engine_map
  end

  def self.read_assign
    open_key = Win32API.new("advapi32", "RegOpenKeyExA", "LPLLP", "L")
    query = Win32API.new("advapi32", "RegQueryValueExA", "LPLLPP", "L")
    close = Win32API.new("advapi32", "RegCloseKey", "L", "L")
    handle = [0].pack("L")
    return nil unless open_key.call(HKEY_CURRENT_USER, "Software\\Enterbrain\\RGSS3", 0, KEY_READ, handle) == 0
    key = handle.unpack("L")[0]
    data = "\0" * 64
    size = [64].pack("L")
    ok = query.call(key, "ButtonAssign", 0, 0, data, size) == 0
    close.call(key)
    return nil unless ok
    data.unpack("C8")
  rescue StandardError
    nil
  end

  # if this cannot be worked out the pad still works, it just also reacts while alt tabbed
  def self.focused?
    @find ||= Win32API.new("user32", "FindWindowA", "PP", "L")
    @foreground ||= Win32API.new("user32", "GetForegroundWindow", "", "L")
    @window ||= @find.call("RGSS Player", nil)
    @window == 0 || @foreground.call == @window
  rescue StandardError
    true
  end

  def self.read_slot(slot)
    buffer = "\0" * 16
    result = @get_state.call(slot, buffer)
    return nil unless result == 0
    buffer.unpack("LSCCssss")
  end

  def self.scan_slots
    @slots = []
    4.times { |slot| @slots << slot if read_slot(slot) }
  end

  # an empty slot is slow to ask about, so they are only checked now and then
  def self.poll
    return if @broken
    get_state
    return unless @get_state
    @scan -= 1
    if @scan <= 0
      scan_slots
      @scan = SCAN_EVERY
    end
    buttons = 0
    lx = 0
    ly = 0
    rt = 0
    connected = false
    if focused?
      @slots.dup.each do |slot|
        state = read_slot(slot)
        unless state
          @slots.delete(slot)
          next
        end
        connected = true
        buttons |= state[1]
        rt = state[3] if state[3] > rt
        lx = state[4] if state[4].abs > lx.abs
        ly = state[5] if state[5].abs > ly.abs
      end
    end
    apply(connected, buttons, rt, lx, ly)
  rescue StandardError
    @broken = true
    @held = {}
    @ghost = {}
  end

  def self.stick_axis(name, active, value)
    limit = @stick[name] ? STICK_OFF : STICK_ON
    @stick[name] = active && value >= limit
  end

  def self.apply(connected, buttons, rt, lx, ly)
    down = {}
    if connected
      ACTIONS.each { |bit, key| down[key] = true if buttons & bit != 0 }
      down[:CTRL] = true if rt >= TRIGGER_ON
      down[:UP] = true if stick_axis(:up, true, ly) || buttons & DPAD_UP != 0
      down[:DOWN] = true if stick_axis(:down, true, -ly) || buttons & DPAD_DOWN != 0
      down[:LEFT] = true if stick_axis(:left, true, -lx) || buttons & DPAD_LEFT != 0
      down[:RIGHT] = true if stick_axis(:right, true, lx) || buttons & DPAD_RIGHT != 0
      engine_map.each do |bit, key|
        @ghost[key] = GHOST_FRAMES if buttons & bit != 0
      end
    else
      @stick = {}
    end
    @ghost.keys.each do |key|
      @ghost[key] -= 1
      @ghost.delete(key) if @ghost[key] < 0
    end
    fresh = {}
    down.keys.each { |key| fresh[key] = (@held[key] || 0) + 1 }
    @held = fresh
  end

  def self.symbol(key)
    key.is_a?(Integer) ? KEY_CODES[key] : key
  end

  def self.press?(key)
    @held[symbol(key)] ? true : false
  end

  def self.trigger?(key)
    @held[symbol(key)] == 1
  end

  def self.repeat?(key)
    count = @held[symbol(key)]
    return false unless count
    return true if count == 1
    count >= REPEAT_START && (count - REPEAT_START) % REPEAT_EVERY == 0
  end

  # the engine reads the same pad its own way, so its report of a held button is not a key press
  def self.ghost?(key)
    @ghost[symbol(key)] ? true : false
  end

  def self.dir8
    x = (@held[:RIGHT] ? 1 : 0) - (@held[:LEFT] ? 1 : 0)
    y = (@held[:UP] ? 1 : 0) - (@held[:DOWN] ? 1 : 0)
    return 0 if x == 0 && y == 0
    5 + x + y * 3
  end

  def self.dir4
    d = dir8
    return d if d == 0 || d.even?
    # on a diagonal the newest direction wins so turning corners feels right
    vertical = @held[:UP] || @held[:DOWN]
    across = @held[:LEFT] || @held[:RIGHT]
    across <= vertical ? (@held[:LEFT] ? 4 : 6) : (@held[:UP] ? 8 : 2)
  end
end

module Input
  class << self
    alias rando_update update unless method_defined?(:rando_update)
    def update
      rando_update
      RandoPad.poll
    end

    alias rando_press? press? unless method_defined?(:rando_press?)
    def press?(key)
      RandoPad.press?(key) || (rando_press?(key) && !RandoPad.ghost?(key))
    end

    alias rando_trigger? trigger? unless method_defined?(:rando_trigger?)
    def trigger?(key)
      RandoPad.trigger?(key) || (rando_trigger?(key) && !RandoPad.ghost?(key))
    end

    alias rando_repeat? repeat? unless method_defined?(:rando_repeat?)
    def repeat?(key)
      RandoPad.repeat?(key) || (rando_repeat?(key) && !RandoPad.ghost?(key))
    end

    alias rando_dir4 dir4 unless method_defined?(:rando_dir4)
    def dir4
      d = RandoPad.dir4
      d > 0 ? d : rando_dir4
    end

    alias rando_dir8 dir8 unless method_defined?(:rando_dir8)
    def dir8
      d = RandoPad.dir8
      d > 0 ? d : rando_dir8
    end
  end
end
