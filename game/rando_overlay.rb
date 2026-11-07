# Tells the stream overlay what has happened so far and never anything still hidden
# Everything here is wrapped so a problem turns the overlay off and the game carries on

module RandoOverlay
  FILE = Rando::DIR + "/overlay/state.js"
  SCAN_FRAMES = 20
  WRITE_FRAMES = 60
  COVENANT_SWITCHES = [434, 431, 432, 433]
  SLAIN_SWITCHES = [179, 178, 176, 177]
  CINDERELLA_SWITCH = 553
  BAPHOMET_RING = 113
  MARY_SUE_TROOP = 236
  BAPHOMET_MAP = 133
  BAPHOMET_EVENT = 7
  ENDING_SWITCHES = { 442 => "A", 443 => "B", 444 => "C", 456 => "D" }
  BOOK_IDS = (273..304).to_a
  LIBRARY_VARIABLE = 46
  SIN_VARIABLE = 38
  DEATHS_VARIABLE = 39
  LAP_VARIABLE = 47

  @frames = 0
  @since_write = 0
  @written = nil
  @dead = false
  @boss = nil

  def self.guard
    yield unless @dead
  rescue StandardError => e
    @error = e
    @dead = true
  end

  def self.world
    $game_system && $game_system.rando
  end

  def self.now
    Graphics.frame_count.to_f / Graphics.frame_rate
  end

  def self.log_for(r)
    r[:log] ||= { :start => 0.0, :rooms => {}, :recruits => {}, :covenants => {},
                  :extras => {}, :beaten => {}, :area => "", :ended => nil, :letter => nil }
  end

  def self.changed
    @since_write = WRITE_FRAMES
  end

  def self.boss_slot?(troop)
    unless @boss_slots
      @boss_slots = {}
      RandoData::BOSSES.each { |b| @boss_slots[b[0]] = true }
      RandoData::PRINCESSES.each { |p| @boss_slots[p[:troop]] = true }
    end
    @boss_slots[troop] ? true : false
  end

  # --- what happened -----------------------------------------------------------

  def self.fight(troop)
    guard do
      r = world
      next unless r
      @boss = nil
      @mary_sue = troop == MARY_SUE_TROOP
      slot = troop % Rando::SLOT_FIGHT_BASE
      next unless troop >= Rando::SLOT_FIGHT_BASE || boss_slot?(troop)
      @boss = slot
    end
  end

  def self.battle_over(result)
    guard do
      r = world
      next unless r
      log = log_for(r)
      log[:beaten][@boss] = true if result == 0 && @boss
      if result == 0 && @mary_sue && !log[:extras]["Mary Sue"]
        log[:extras]["Mary Sue"] = now - log[:start]
        changed
      end
      @mary_sue = false
      @boss = nil
    end
  end

  def self.recruited(slot_actor)
    guard do
      r = world
      next unless r
      log = log_for(r)
      next if log[:recruits][slot_actor]
      log[:recruits][slot_actor] = now - log[:start]
      changed
    end
  end

  def self.baphomet
    guard do
      r = world
      next unless r
      log = log_for(r)
      next if log[:extras]["Baphomet"]
      log[:extras]["Baphomet"] = now - log[:start]
      changed
    end
  end

  # new game plus starts a fresh lap of the same run
  def self.new_lap
    guard do
      r = world
      next unless r
      r[:log] = nil
      log_for(r)[:start] = now
    end
  end

  # --- what is on screen ---------------------------------------------------------

  def self.reveal_room(r, log, room)
    return if log[:rooms][room]
    log[:rooms][room] = true
    changed
  end

  def self.scan_rooms(r, log)
    ip = $game_map.interpreter
    if ip.running?
      RandoData::PRINCESSES.each_with_index do |p, room|
        reveal_room(r, log, room) if $game_map.map_id == p[:map] && ip.event_id == p[:ev]
      end
    end
    r[:rooms].each_with_index do |who, room|
      made = $game_switches[COVENANT_SWITCHES[who]]
      reveal_room(r, log, room) if made || $game_switches[SLAIN_SWITCHES[who]]
      next if !made || log[:covenants][who]
      log[:covenants][who] = now - log[:start]
      changed
    end
  end

  def self.scan(r, log)
    return unless $game_map && $game_switches && $game_party
    name = $game_map.display_name.to_s
    log[:area] = name unless name.strip.empty?
    scan_rooms(r, log)
    scan_books(log)
    if $game_switches[CINDERELLA_SWITCH] && !log[:extras]["Cinderella"]
      log[:extras]["Cinderella"] = now - log[:start]
      changed
    end
    return if log[:ended]
    ENDING_SWITCHES.each do |switch_id, letter|
      next unless $game_switches[switch_id]
      log[:ended] = now - log[:start]
      log[:letter] = letter
      changed
      break
    end
  end

  # a book handed in at the library leaves the bag, so a book once seen stays counted
  def self.scan_books(log)
    log[:books] ||= {}
    BOOK_IDS.each do |id|
      next if log[:books][id] || $game_party.item_number($data_items[id]) <= 0
      log[:books][id] = true
      changed
    end
  end

  def self.books_held(log)
    held = BOOK_IDS.count { |id| $game_party.item_number($data_items[id]) > 0 }
    [[held + $game_variables[LIBRARY_VARIABLE], (log[:books] || {}).size].max, BOOK_IDS.size].min
  end

  def self.books_list(log)
    seen = log[:books] || {}
    BOOK_IDS.map { |id| { "name" => $data_items[id].name, "have" => seen[id] ? true : false } }
  end

  def self.phase(log)
    scene = SceneManager.scene
    return "title" if scene.is_a?(Scene_Title) || scene.is_a?(Scene_RandoSetup)
    log[:ended] ? "ended" : "play"
  end

  def self.rooms_state(r, log)
    (0...RandoData::PRINCESSES.size).map do |room|
      known = log[:rooms][room]
      who = r[:rooms][room]
      row = { "room" => RandoData::PRINCESSES[room][:name], "who" => nil, "covenant" => nil, "slain" => false }
      if known
        row["who"] = RandoData::PRINCESSES[who][:name]
        row["covenant"] = log[:covenants][who]
        row["slain"] = $game_switches[SLAIN_SWITCHES[who]] ? true : false
      end
      row
    end
  end

  def self.recruits_state(r, log)
    RandoData::COMPANIONS.map do |c|
      at = log[:recruits][c[:actor]]
      { "spot" => c[:name], "who" => at ? Rando.companion(r[:persona][c[:actor]])[:name] : nil, "at" => at }
    end
  end

  def self.state(r, log)
    lead = $game_party.members[0]
    { "phase" => phase(log), "beat" => Time.now.to_f, "version" => Rando::VERSION, "seed" => Rando.seed_text(r[:seed]),
      "igt" => log[:ended] || (now - log[:start]), "lap" => $game_variables[LAP_VARIABLE],
      "area" => log[:area], "level" => lead ? lead.level : 1, "souls" => $game_party.gold,
      "deaths" => $game_variables[DEATHS_VARIABLE], "sin" => $game_variables[SIN_VARIABLE],
      "books" => books_held(log), "books_total" => BOOK_IDS.size, "books_list" => books_list(log),
      "bosses" => log[:beaten].size,
      "rooms" => rooms_state(r, log), "recruits" => recruits_state(r, log),
      "extras" => log[:extras], "ending" => log[:letter] }
  end

  def self.idle_state
    { "phase" => "title", "beat" => Time.now.to_f, "version" => Rando::VERSION, "seed" => nil }
  end

  # --- writing --------------------------------------------------------------------

  def self.json(value)
    case value
    when nil then "null"
    when true then "true"
    when false then "false"
    when Integer then value.to_s
    when Float then sprintf("%.3f", value)
    when Hash then "{" + value.map { |k, v| json(k.to_s) + ":" + json(v) }.join(",") + "}"
    when Array then "[" + value.map { |v| json(v) }.join(",") + "]"
    else
      text = value.to_s.dup.force_encoding("UTF-8")
      "\"" + text.gsub(/[\\"\x00-\x1f]/) { |c| sprintf("\\u%04x", c.ord) } + "\""
    end
  end

  def self.write(state)
    return unless File.directory?(File.dirname(FILE))
    begin
      File.open(FILE, "wb") { |f| f.write("window.__randoState(" + json(state) + ");\n") }
    rescue SystemCallError, IOError
      # the page was reading it, the next beat tries again
      nil
    end
  end

  def self.tick
    return if @dead
    @frames += 1
    @since_write += 1
    return if @frames < SCAN_FRAMES && @since_write < WRITE_FRAMES
    guard do
      @frames = 0
      r = world
      if r
        log = log_for(r)
        scan(r, log)
        next if @since_write < WRITE_FRAMES
        @since_write = 0
        write(state(r, log))
      elsif @since_write >= WRITE_FRAMES
        @since_write = 0
        write(idle_state)
      end
    end
  end
end

module Rando
  class << self
    alias overlay_recruit recruit
    def recruit(slot_actor)
      overlay_recruit(slot_actor)
      RandoOverlay.recruited(slot_actor)
    end

    alias overlay_reset_recruits reset_recruits
    def reset_recruits
      overlay_reset_recruits
      RandoOverlay.new_lap
    end
  end
end

class Game_Interpreter
  alias overlay_command_301 command_301
  def command_301
    RandoOverlay.fight(@params[1]) if !$game_party.in_battle && @params[0] == 0
    overlay_command_301
  end

  alias overlay_command_128 command_128
  def command_128
    RandoOverlay.baphomet if @map_id == RandoOverlay::BAPHOMET_MAP && @event_id == RandoOverlay::BAPHOMET_EVENT && @params[0] == RandoOverlay::BAPHOMET_RING && @params[1] == 0
    overlay_command_128
  end
end

module BattleManager
  class << self
    alias overlay_battle_end battle_end
    def battle_end(result)
      RandoOverlay.battle_over(result)
      overlay_battle_end(result)
    end
  end
end

class Scene_Base
  alias overlay_update_basic update_basic
  def update_basic
    overlay_update_basic
    RandoOverlay.tick
  end
end
