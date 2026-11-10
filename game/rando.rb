# BLACK SOULS randomizer
# Rolled in game from the seed and options set on the title screen

module Rando
  VERSION = "0.6.0"
end

class RandoRng
  def initialize(seed, stream)
    @state = seed.to_i & 0xFFFFFFFF
    stream.to_s.each_byte { |b| @state = (@state * 31 + b) & 0xFFFFFFFF }
    8.times { step }
  end

  def step
    @state = (@state * 1664525 + 1013904223) & 0xFFFFFFFF
  end

  def below(n)
    (step >> 8) % n
  end

  def shuffle(list)
    out = list.dup
    (out.size - 1).downto(1) do |i|
      j = below(i + 1)
      out[i], out[j] = out[j], out[i]
    end
    out
  end

  def pick(list)
    list[below(list.size)]
  end
end

module Rando
  DIR = "Randomizer"
  SETTINGS = DIR + "/settings.txt"
  INVITATION = 52
  ASHES_ITEM = 55
  JEANNE_ACTOR = 12
  BEHEMOTH_ROUTE_SWITCH = 35
  RAPUNZEL_DEAD_SWITCH = 178
  PRINCESS_COUNT_VARIABLE = 34
  FROG = 0
  RAPUNZEL = 1
  SNOW_WHITE = 2
  MERMAID = 3
  MERMAID_HOME_MAP = 72
  SNOW_SCENE_EVENTS = [7, 21, 22]
  BEHEMOTH_RETURN_EVENT = 12
  SECOND_PHASE_SWITCHES = [58, 59]
  SECOND_PHASE_TROOPS = [159, 200]
  SLOT_FIGHT_BASE = 10000
  HANSEL_TROOP = 136
  # the same fight reached from the other choice at the witch's house
  HANSEL_TWIN_TROOP = 310
  WITCH_FLAME_KEY = "22:21:"
  # the brother and sister also ambush you alone in the forest, those fights go to whoever took the house
  HANSEL_SOLO_TROOPS = [317, 318]
  # the tortoise and hare knights are rivals met again and again, the fight with both stands for all of them
  KNIGHTS_TROOP = 189
  KNIGHTS_OTHER_TROOPS = [72, 73, 186, 187]
  # the second Cinderella fight follows the first when the final bosses are shuffled
  CINDERELLA_TROOP = 161
  CINDERELLA_TWIN_TROOP = 315
  BEAUTY_TROOP = 150
  BEAUTY_BOOK = 288
  # her arena and the two places the other choices pay out her book
  BEAUTY_BOOK_EVENTS = [[95, 102], [88, 92], [114, 35]]
  ROUTE_SET_GRAPHIC = 41
  RECRUITED_BASE = 3100
  LOST_BASE = 3200
  LOST_STRIDE = 2
  LEAF_ACTOR = 13
  LEAF_MET_SWITCH = 16
  NEW_GAME_PLUS_SWITCH = 15
  FLAG_QUEST = 1
  FLAG_PROLOGUE = 4
  FLAG_BOOK = 8
  FLAG_COVENANT = 16

  OPTIONS = [
    [:enabled, "Randomizer", "Turn this off to play the normal game."],
    [:loot, "Random loot", "Shuffles chests and pickups. The Invitation is always placed where you can reach it."],
    [:drops, "Random drops", "Shuffles what enemies drop, boss gear included. Fairytale books stay with their bosses."],
    [:books, "Fairytale books in chests", "Off means books only come from fairytale bosses and story events. On also hides some in chests."],
    [:covenants, "Covenant rings in chests", "Off means a Favor ring only comes from its covenant. On can hide two of them in chests."],
    [:princesses, "Shuffle princess rooms", "The four demonic princesses swap rooms. Each one keeps her own fight and covenant."],
    [:bosses, "Shuffle bosses", "Fairytale bosses trade arenas with each other, the rest likewise. Story flags stay put."],
    [:special, "Shuffle final bosses", "Final bosses and mimics join the fairytale bosses, books drop where they normally do. Best left off."],
    [:scaling, "Scale bosses", "Scales a shuffled boss to the fight it replaces."],
    [:enemies, "Shuffle enemies", "Swaps enemy groups, scaled to the group they replace."],
    [:prologue, "Shuffle the prologue", "Includes the prologue pigs and dragon in the shuffles above."],
    [:companions, "Shuffle companions", "Where you would meet one companion you get another. She then waits at her usual Holy Forest spot."]
  ]
  DEFAULTS = { :enabled => true, :loot => true, :drops => true, :books => false, :covenants => false, :princesses => true, :bosses => true,
               :scaling => true, :enemies => true, :prologue => true, :companions => true, :special => false }

  def self.settings
    @settings ||= load_settings
  end

  def self.load_settings
    out = DEFAULTS.dup
    out[:seed] = fresh_seed
    begin
      if File.exist?(SETTINGS)
        File.open(SETTINGS, "rb") { |f| f.read }.split(/\r?\n/).each do |line|
          k, v = line.split("=", 2)
          next if k.nil? || v.nil?
          if k == "seed"
            out[:seed] = v.to_i
          elsif DEFAULTS.key?(k.to_sym)
            out[k.to_sym] = v == "true"
          end
        end
      end
    rescue StandardError
      nil
    end
    out
  end

  def self.save_settings
    Dir.mkdir(DIR) unless File.directory?(DIR)
    body = settings.keys.map { |k| k.to_s + "=" + settings[k].to_s }.join("\n") + "\n"
    File.open(SETTINGS, "wb") { |f| f.write(body) }
  rescue StandardError
    nil
  end

  def self.fresh_seed
    rand(100000000)
  end

  def self.wrap(text, width)
    lines = [""]
    text.split(" ").each do |word|
      lines << "" if lines.last.size + word.size + 1 > width
      lines[-1] = (lines.last + " " + word).strip
    end
    lines.join("
")
  end

  def self.seed_text(seed)
    sprintf("%08d", seed.to_i)
  end

  def self.data
    $game_system && $game_system.rando
  end

  # --- rolling -------------------------------------------------------------

  def self.roll(opts)
    out = { :version => VERSION, :seed => opts[:seed], :opts => opts.dup, :place => {}, :spoiler => [] }
    # saves rolled before this keep paying her book at her own arena
    out[:beauty_carries] = !opts[:books] && !(opts[:special] && opts[:bosses])
    out[:rooms] = roll_rooms(opts)
    out[:persona] = roll_persona(opts)
    out[:swaps] = roll_swaps(opts, out[:rooms], out[:persona])
    assign = opts[:loot] ? roll_loot(opts, out) : nil
    out[:drops] = opts[:drops] ? roll_drops(opts, out, assign) : []
    place_witch_flame(out)
    out
  end

  def self.witch_flame?(row)
    row[0][0].start_with?(WITCH_FLAME_KEY)
  end

  # the witch's house can pay its book without the fight, it pays the book of whoever moved in
  def self.place_witch_flame(out)
    swap = out[:swaps][HANSEL_TROOP]
    # a boss that brings its book pays that book here, otherwise the house keeps paying its own
    book = swap && (swap[6] ? carried_book(swap[0], out[:opts]) : RandoData::FAIRY_BOOKS[HANSEL_TROOP])
    return unless book
    RandoData::LOCATIONS.each do |l|
      next unless witch_flame?(l)
      l[0].each { |k| out[:place][k] = [0, book, 1] }
      out[:spoiler] << [l[6], [0, book, 1]]
    end
  end

  # Beauty pays her book in dialogue rather than as a drop, with books in chests it is a chest item instead
  def self.carried_book(troop, opts)
    RandoData::FAIRY_BOOKS[troop] || (troop == BEAUTY_TROOP && !opts[:books] ? BEAUTY_BOOK : nil)
  end

  def self.beauty_away?
    r = data
    r && r[:beauty_carries] && r[:swaps][BEAUTY_TROOP] ? true : false
  end

  def self.roll_rooms(opts)
    order = [0, 1, 2, 3]
    return order unless opts[:princesses]
    RandoRng.new(opts[:seed], "princesses").shuffle(order)
  end

  def self.roll_persona(opts)
    actors = RandoData::COMPANIONS.map { |c| c[:actor] }
    placed = actors
    if opts[:companions]
      rng = RandoRng.new(opts[:seed], "companions")
      # nobody keeps her own spot, otherwise a shuffled seed can look like the normal game
      loop do
        placed = rng.shuffle(actors)
        break if (0...actors.size).none? { |i| placed[i] == actors[i] }
      end
    end
    out = {}
    actors.each_with_index { |a, i| out[a] = placed[i] }
    out
  end

  # slot and fought are [troop, hp, atk, def, agi, gold, visible members]
  def self.scale(slot, fought, on)
    return [fought[0], 1.0, 1.0, 1.0, 1.0, 1.0] unless on
    crowd = Math.sqrt(slot[6].to_f / fought[6])
    gold = fought[5] > 0 ? slot[5].to_f / fought[5] : 1.0
    [fought[0], slot[1].to_f / fought[1], crowd * slot[2] / fought[2], slot[3].to_f / fought[3],
     slot[4].to_f / fought[4], gold]
  end

  def self.boss_row(troop)
    RandoData::BOSSES.find { |b| b[0] == troop } || RandoData::SPECIAL_BOSSES.find { |b| b[0] == troop }
  end

  def self.roll_swaps(opts, rooms, persona)
    swaps = {}
    skip = opts[:prologue] ? [] : RandoData::PROLOGUE_TROOPS
    if opts[:bosses]
      pool = RandoData::BOSSES.reject do |b|
        skip.include?(b[0]) || b[0] == HANSEL_TWIN_TROOP || HANSEL_SOLO_TROOPS.include?(b[0]) || KNIGHTS_OTHER_TROOPS.include?(b[0])
      end
      fairy = pool.select { |b| RandoData::FAIRY_BOSSES.include?(b[0]) }
      shuffle_group(pool - fairy, "bosses", opts, swaps, opts[:scaling], true)
      # final bosses and chests that bite join the fairytale bosses, a book could then end up behind a final arena,
      # so every book stays with its home arena and whoever fights there pays it
      special = opts[:special] ? RandoData::SPECIAL_BOSSES.reject { |b| b[0] == CINDERELLA_TWIN_TROOP } : []
      shuffle_group(fairy + special, "fairy", opts, swaps, opts[:scaling], true)
      # otherwise a fairytale boss brings its own book, everything else pays out what its fight paid out
      fairy.each { |b| swaps[b[0]] << true if swaps[b[0]] } if special.empty?
      if swaps[HANSEL_TROOP]
        swaps[HANSEL_TWIN_TROOP] = swaps[HANSEL_TROOP].dup
        house = boss_row(swaps[HANSEL_TROOP][0])
        # these fights pay their own shuffled drops so no book comes twice
        HANSEL_SOLO_TROOPS.each do |t|
          slot = boss_row(t)
          swaps[t] = scale(slot, house, opts[:scaling]) if slot && house
        end
      end
      # every knight fight gets whoever took the fight with both, so the knights turn up in one arena only
      if opts[:bosses] && swaps[KNIGHTS_TROOP]
        rival = boss_row(swaps[KNIGHTS_TROOP][0])
        KNIGHTS_OTHER_TROOPS.each do |t|
          slot = boss_row(t)
          swaps[t] = scale(slot, rival, opts[:scaling]) if slot && rival
        end
      end
      if swaps[CINDERELLA_TROOP]
        twin = boss_row(CINDERELLA_TWIN_TROOP)
        queen = boss_row(swaps[CINDERELLA_TROOP][0])
        swaps[CINDERELLA_TWIN_TROOP] = scale(twin, queen, opts[:scaling]) if twin && queen
      end
    end
    if opts[:enemies]
      pool = RandoData::ENEMIES.reject { |e| skip.include?(e[0]) }
      shuffle_enemies(pool, opts, swaps)
    end
    rooms.each_with_index do |who, room|
      next if who == room
      own = RandoData::PRINCESSES[who]
      swaps[own[:troop]] = scale(RandoData::PRINCESSES[room][:stats], own[:stats], opts[:scaling])
    end
    # a recruit encounter with a fight has you fight whoever you recruit there
    RandoData::COMPANIONS.each do |c|
      next if persona[c[:actor]] == c[:actor] || !c[:fight]
      swaps[SLOT_FIGHT_BASE + c[:fight]] = scale(c[:fight_stats], companion(persona[c[:actor]])[:main_stats], opts[:scaling])
    end
    swaps
  end

  # a moved group never leaves a fight looking the same, two troops of one boss count as the same
  def self.shuffle_group(pool, stream, opts, swaps, scaled, moved = false)
    rng = RandoRng.new(opts[:seed], stream)
    placed = rng.shuffle(pool)
    while moved && pool.size > 1 && (0...pool.size).any? { |i| placed[i][8] == pool[i][8] }
      placed = rng.shuffle(pool)
    end
    pool.each_with_index do |slot, i|
      next if slot[0] == placed[i][0]
      swaps[slot[0]] = scale(slot, placed[i], scaled)
    end
  end

  # regular enemies keep their shape, a lone enemy only trades with a lone enemy and a group with a group
  def self.shuffle_enemies(pool, opts, swaps)
    solo = pool.select { |t| t[7] == 1 }
    shuffle_group(solo, "enemies solo", opts, swaps, true)
    shuffle_group(pool - solo, "enemies group", opts, swaps, true)
  end

  # regions reachable with or without the Invitation
  def self.reachable(invitation)
    regions = RandoData::REGIONS
    seen = {}
    changed = true
    while changed
      changed = false
      regions.each_with_index do |r, i|
        next if seen[i]
        next unless r[1] < 0 || seen[r[1]]
        ok = case r[2]
             when nil then true
             when "invitation" then invitation
             when "ivern" then seen[RandoData::IVERN_REGION]
             when "princesses" then RandoData::PRINCESS_REGIONS.all? { |p| seen[p] }
             end
        next unless ok
        seen[i] = true
        changed = true
      end
    end
    seen
  end

  def self.location_open?(loc, seen)
    seen[loc[1]]
  end

  def self.safe_spots(locs, seen)
    locs.select { |l| l[5] & (FLAG_QUEST | FLAG_PROLOGUE) == 0 && location_open?(l, seen) }
  end

  # rows left out here keep their normal item in their normal place
  def self.loot_rows(opts)
    RandoData::LOCATIONS.reject do |l|
      witch_flame?(l) || (!opts[:books] && l[5] & FLAG_BOOK != 0) || (!opts[:covenants] && l[5] & FLAG_COVENANT != 0)
    end
  end

  def self.roll_loot(opts, out)
    rng = RandoRng.new(opts[:seed], "loot")
    locs = loot_rows(opts)
    pool = locs.map { |l| [l[2], l[3], l[4]] }
    assign = {}
    # the Invitation goes somewhere reachable without it
    index = pool.index { |p| p[0] == 0 && p[1] == INVITATION }
    if index
      item = pool.delete_at(index)
      assign[rng.pick(safe_spots(locs, reachable(false)))] = item
    end
    books = pool.select { |p| p[0] == 0 && book?(p[1], locs) }
    pool -= books
    free = rng.shuffle(locs.reject { |l| assign[l] })
    safe = free.select { |l| l[5] & (FLAG_QUEST | FLAG_PROLOGUE) == 0 }
    books.each do |item|
      spot = safe.shift
      assign[spot] = item
      free.delete(spot)
    end
    rng.shuffle(pool).each_with_index { |item, i| assign[free[i]] = item }
    locs.each do |l|
      item = assign[l]
      next unless item
      l[0].each { |k| out[:place][k] = item }
      out[:spoiler] << [l[6], item]
    end
    assign
  end

  # rows are [enemy, slot, kind, id, guaranteed, boss], kinds trade within their own group
  def self.roll_drops(opts, out, assign)
    rng = RandoRng.new(opts[:seed], "drops")
    groups = {}
    RandoData::DROPS.each do |d|
      key = [d[5], d[2] == 0 ? 0 : 1, d[4]]
      (groups[key] ||= []) << d
    end
    result = []
    groups.keys.sort.each do |key|
      rows = groups[key]
      items = rng.shuffle(rows.map { |d| [d[2], d[3]] })
      rows.each_with_index { |d, i| result << [d[0], d[1], items[i][0], items[i][1]] }
    end
    trade_boss_gear(rng, result, out, assign) if assign
    result
  end

  # boss gear also trades with gear found in the world
  def self.trade_boss_gear(rng, result, out, assign)
    boss_slots = {}
    RandoData::DROPS.each { |d| boss_slots[[d[0], d[1]]] = true if d[5] == 1 && d[2] != 0 }
    spots = assign.keys.select { |l| assign[l][0] != 0 }
    result.each do |row|
      next unless boss_slots[[row[0], row[1]]]
      next if spots.empty?
      spot = rng.pick(spots)
      given = assign[spot]
      moved = [row[2], row[3], 1]
      row[2], row[3] = given[0], given[1]
      assign[spot] = moved
      spot[0].each { |k| out[:place][k] = moved }
      entry = out[:spoiler].find { |e| e[0] == spot[6] }
      entry[1] = moved if entry
    end
  end

  def self.book?(id, locs)
    @book_ids ||= RandoData::LOCATIONS.select { |l| l[5] & FLAG_BOOK != 0 }.map { |l| l[3] }.uniq
    @book_ids.include?(id)
  end

  # --- data edits -----------------------------------------------------------

  def self.companion(actor)
    RandoData::COMPANIONS.find { |c| c[:actor] == actor }
  end

  def self.pristine
    @pristine ||= begin
      drops = {}
      RandoData::DROPS.each do |d|
        di = $data_enemies[d[0]].drop_items[d[1]]
        drops[[d[0], d[1]]] = [di.kind, di.data_id]
      end
      { :ashes => $data_items[ASHES_ITEM].name, :drops => drops }
    end
  end

  def self.apply_data
    base = pristine
    r = data
    base[:drops].each do |slot, value|
      di = $data_enemies[slot[0]].drop_items[slot[1]]
      di.kind = value[0]
      di.data_id = value[1]
    end
    (r ? r[:drops] : []).each do |row|
      di = $data_enemies[row[0]].drop_items[row[1]]
      di.kind = row[2] + 1
      di.data_id = row[3]
    end
    jeanne = r ? r[:persona][JEANNE_ACTOR] : JEANNE_ACTOR
    $data_items[ASHES_ITEM].name = base[:ashes]
    $data_items[ASHES_ITEM].name = $data_actors[jeanne].name + "'s Ashes" if jeanne != JEANNE_ACTOR
  end

  def self.moved?(princess)
    r = data
    r && r[:rooms][princess] != princess
  end

  # the room a princess ended up in
  def self.room_of(princess)
    data[:rooms].index(princess)
  end

  BOOKS_ALL = 32
  INNER_BOOKS = 8
  BOOKS_ROOM = 24
  BOOK_VARIABLE = 46
  LIBRARY_MAPS = [101, 104]

  def self.books_needed
    r = data
    n = r && r[:opts] && r[:opts][:books_needed]
    n ? [[n.to_i, 1].max, BOOKS_ALL].min : BOOKS_ALL
  end

  # the inner room opens once the books that belong outside it are on their shelves
  def self.patch_library(map, map_id)
    return unless LIBRARY_MAPS.include?(map_id)
    need = books_needed
    return if need >= BOOKS_ALL
    room = [[need - INNER_BOOKS, 0].max, BOOKS_ROOM].min
    wanted = { BOOKS_ROOM => room, BOOKS_ALL => need }
    map.events.each_value do |ev|
      ev.pages.each do |page|
        c = page.condition
        if c.variable_valid && c.variable_id == BOOK_VARIABLE && wanted[c.variable_value]
          c.variable_value = wanted[c.variable_value]
        end
        page.list.each do |cmd|
          p = cmd.parameters
          next unless cmd.code == 111 && p[0] == 1 && p[1] == BOOK_VARIABLE && p[2] == 0 && wanted[p[3]]
          cmd.parameters = p.dup
          cmd.parameters[3] = wanted[p[3]]
        end
      end
    end
  end

  def self.prepare_map(map, map_id)
    r = data
    return unless r
    patch_library(map, map_id)
    rooms = r[:rooms]
    RandoData::PRINCESSES.each_with_index do |room, i|
      next unless room[:map] == map_id && rooms[i] != i
      map.events[room[:ev]] = moved_princess(rooms[i], room, map.events[room[:ev]])
    end
    if map_id == RandoData::PRINCESSES[SNOW_WHITE][:map] && moved?(SNOW_WHITE)
      SNOW_SCENE_EVENTS.each { |id| map.events[id].pages[0].list = [RPG::EventCommand.new] if map.events[id] }
    end
    if map_id == RandoData::PRINCESSES[RAPUNZEL][:map] && moved?(RAPUNZEL)
      strip_rapunzel_death(map.events[BEHEMOTH_RETURN_EVENT])
    end
    sprites = {}
    RandoData::COMPANIONS.each do |c|
      who = r[:persona][c[:actor]]
      other = companion(who)
      # a save from an older build can name someone who is no longer in the table
      next if who == c[:actor] || !other
      c[:chars].each { |ch| sprites[ch] = other[:chars][0] } if c[:sprite_maps].include?(map_id)
      rewrite_encounter(map, c, other, r) if c[:slot_map] == map_id
    end
    # one pass over the map, two spots on one map must not swap the same sprite twice
    swap_sprites(map, sprites) unless sprites.empty?
    hide_unrecruited_leaf(map) if map_id == companion(LEAF_ACTOR)[:hub_event][0] && companion(r[:persona][LEAF_ACTOR]) && r[:persona][LEAF_ACTOR] != LEAF_ACTOR
  end

  # only walking sprites change, the portraits in dialogue stay as they are
  def self.swap_sprites(map, sprites)
    map.events.each_value do |ev|
      ev.pages.each do |page|
        g = page.graphic
        wanted = g && sprites[[g.character_name, g.character_index]]
        if wanted
          g.character_name = wanted[0]
          g.character_index = wanted[1]
        end
        swap_route(page.move_route, sprites)
        page.list.each do |c|
          swap_route(c.parameters[1], sprites) if c.code == 205
          swap_move(c.parameters[0], sprites) if c.code == 505
        end
      end
    end
  end

  def self.swap_route(route, sprites)
    return unless route && route.list
    route.list.each { |m| swap_move(m, sprites) }
  end

  def self.swap_move(move, sprites)
    return unless move && move.code == ROUTE_SET_GRAPHIC
    wanted = sprites[[move.parameters[0], move.parameters[1]]]
    move.parameters = [wanted[0], wanted[1]] if wanted
  end

  # her death and capture switches inside a spot that holds someone else, so the real one is never touched
  def self.lost_switch(slot, id)
    LOST_BASE + slot[:actor] * LOST_STRIDE + slot[:lost].index(id)
  end

  # commands are replaced one for one, pickups are found by their position in the page
  def self.rewrite_encounter(map, slot, other, r)
    script = recruit_script(slot, other)
    lost = slot[:lost] || []
    moved = {}
    moved[slot[:cond]] = RECRUITED_BASE + slot[:actor] if slot[:cond]
    # she waits on the encounter of the one she needs, never on the real one, so a spot cannot wait on itself
    need = slot[:needs] && companion(slot[:needs])
    moved[need[:hub][0]] = RECRUITED_BASE + need[:actor] if need
    lost.each { |id| moved[id] = lost_switch(slot, id) }
    slot[:slot_events].each do |id|
      ev = map.events[id]
      next unless ev
      ev.pages.each do |page|
        cond = page.condition
        cond.switch1_id = moved[cond.switch1_id] if cond.switch1_valid && moved[cond.switch1_id]
        cond.switch2_id = moved[cond.switch2_id] if cond.switch2_valid && moved[cond.switch2_id]
        page.list.each do |c|
          if c.code == 121 && c.parameters[0] == c.parameters[1] && lost.include?(c.parameters[0])
            p = c.parameters.dup
            p[0] = p[1] = moved[p[0]]
            c.parameters = p
          elsif c.code == 111 && c.parameters[0] == 0 && lost.include?(c.parameters[1])
            p = c.parameters.dup
            p[1] = moved[p[1]]
            c.parameters = p
          elsif c.code == 121 && c.parameters[2] == 0 && c.parameters[0] == c.parameters[1] && slot[:triggers].include?(c.parameters[0])
            c.code = 355
            c.parameters = [script]
          elsif c.code == 117 && c.parameters[0] == slot[:learn]
            c.code = 355
            c.parameters = [script]
          elsif c.code == 301 && c.parameters[0] == 0 && c.parameters[1] == slot[:fight]
            key = SLOT_FIGHT_BASE + slot[:fight]
            next unless r[:swaps][key]
            p = c.parameters.dup
            p[1] = key
            c.parameters = p
          end
        end
      end
    end
  end

  def self.recruit_script(slot, other)
    text = "Rando.recruit(#{slot[:actor]})"
    text += "\n@params = [#{other[:learn]}]\ncommand_117" if other[:learn]
    text
  end

  # the encounter is used up and the real character takes her vanilla place
  def self.recruit(slot_actor)
    r = data
    return unless r
    $game_switches[RECRUITED_BASE + slot_actor] = true
    own = companion(slot_actor)
    (own[:after] || []).each { |id| $game_switches[id] = true } if own
    other = companion(r[:persona][slot_actor])
    other[:hub].each { |id| $game_switches[id] = true } if other
  end

  # meeting her also opens other hub events so that switch stays, only her own hub spot waits for the recruit
  def self.hide_unrecruited_leaf(map)
    leaf = companion(LEAF_ACTOR)
    ev = map.events[leaf[:hub_event][1]]
    return unless ev
    ev.pages.each do |page|
      cond = page.condition
      cond.switch1_id = leaf[:hub][0] if cond.switch1_valid && cond.switch1_id == LEAF_MET_SWITCH
      cond.switch2_id = leaf[:hub][0] if cond.switch2_valid && cond.switch2_id == LEAF_MET_SWITCH
    end
  end

  # a new playthrough opens the encounters again
  def self.reset_recruits
    return unless data
    RandoData::COMPANIONS.each do |c|
      $game_switches[RECRUITED_BASE + c[:actor]] = false
      $game_switches[c[:hub][0]] = false if c[:hub][0] > RECRUITED_BASE - 200
      (c[:lost] || []).each { |id| $game_switches[lost_switch(c, id)] = false }
    end
  end


  def self.source_event(princess)
    home = RandoData::PRINCESSES[princess]
    Marshal.load(Marshal.dump(load_data(sprintf("Data/Map%03d.rvdata2", home[:map])).events[home[:ev]]))
  end

  def self.moved_princess(who, room, old)
    home = RandoData::PRINCESSES[who]
    ev = source_event(who)
    ev.id = old.id
    ev.x = old.x
    ev.y = old.y
    add_snow_scene(ev) if who == SNOW_WHITE
    ev.pages.each do |page|
      page.list.each do |c|
        retarget(c, home[:ev])
        retarget_transfer(c, room) if who == MERMAID
      end
    end
    ev
  end

  def self.retarget(command, old_id)
    return unless [205, 212, 213].include?(command.code)
    command.parameters = command.parameters.dup
    command.parameters[0] = 0 if command.parameters[0] == old_id
  end

  # her send you to the entrance choice goes to the room she is in now
  def self.retarget_transfer(command, room)
    return unless command.code == 201 && command.parameters[1] == MERMAID_HOME_MAP
    p = command.parameters.dup
    p[1], p[2], p[3] = room[:ret][0], room[:ret][1], room[:ret][2]
    command.parameters = p
  end

  # her scene after Cinderella normally starts from floor tiles in her own room
  def self.add_snow_scene(ev)
    home = RandoData::PRINCESSES[SNOW_WHITE]
    src = load_data(sprintf("Data/Map%03d.rvdata2", home[:map])).events[SNOW_SCENE_EVENTS[0]].pages[0]
    copy = Marshal.load(Marshal.dump(src))
    copy.list = copy.list.reject { |c| c.code == 201 }
    base = ev.pages[3]
    page = Marshal.load(Marshal.dump(base))
    page.condition = copy.condition
    page.list = copy.list
    page.trigger = 0
    after = ev.pages.index { |p| p.condition.switch1_valid && p.condition.switch1_id == 502 }
    ev.pages.insert(after || 4, page)
  end

  # Behemoth still comes to the tower but she dies where she is, so the count is settled once
  def self.strip_rapunzel_death(ev)
    return unless ev
    page = ev.pages[0]
    page.list = page.list.reject do |c|
      (c.code == 121 && c.parameters[0] == RAPUNZEL_DEAD_SWITCH) ||
        (c.code == 122 && c.parameters[0] == PRINCESS_COUNT_VARIABLE)
    end
  end

  def self.behemoth_route_set
    return unless moved?(RAPUNZEL)
    return if $game_switches[RAPUNZEL_DEAD_SWITCH]
    $game_switches[RAPUNZEL_DEAD_SWITCH] = true
    $game_variables[PRINCESS_COUNT_VARIABLE] += 1
  end

  # a moved boss brings the music and background of its own fight, some bosses are drawn in the background
  def self.dress_battle(arena, fought)
    return if arena == fought || !$game_system || !$game_map
    music = RandoData::BATTLE_MUSIC[fought]
    back = RandoData::BATTLE_BACKS[fought]
    return unless music || back || RandoData::BATTLE_BACKS[arena]
    $game_temp.rando_look = [$game_system.battle_bgm, $game_map.battleback1_name, $game_map.battleback2_name]
    $game_system.battle_bgm = RPG::BGM.new(music[0], music[1], music[2]) if music
    # a room drawn around its own boss falls back to the plain view for anyone else
    set_battleback(back ? back[0] : nil, back ? back[1] : nil) if back || RandoData::BATTLE_BACKS[arena]
  end

  # stored straight on the map, the game's own change command would redraw a battle that is ending
  def self.set_battleback(floor, wall)
    $game_map.instance_variable_set(:@battleback1_name, floor)
    $game_map.instance_variable_set(:@battleback2_name, wall)
  end

  # the room's own music and background are put back once the fight is over
  def self.undress_battle
    look = $game_temp && $game_temp.rando_look
    return unless look
    $game_temp.rando_look = nil
    $game_system.battle_bgm = look[0]
    set_battleback(look[1], look[2])
  end

  # what a fight paid out in the normal game, forms it changes into included
  def self.slot_enemies(slot)
    troop = $data_troops[slot]
    ids = troop.members.map { |m| m.enemy_id }
    troop.pages.each do |page|
      page.list.each { |c| ids << c.parameters[1] if c.code == 336 }
    end
    ids.uniq
  end

  def self.slot_drops(slot, rate)
    out = []
    slot_enemies(slot).each do |id|
      $data_enemies[id].drop_items.each do |di|
        next unless di.kind > 0 && rand * di.denominator < rate
        table = [nil, $data_items, $data_weapons, $data_armors][di.kind]
        item = table[di.data_id]
        out << item if item && !out.include?(item)
      end
    end
    out
  end

  # --- spoiler ---------------------------------------------------------------

  def self.item_name(item)
    table = [$data_items, $data_weapons, $data_armors][item[0]]
    name = table[item[1]] ? table[item[1]].name : "?"
    item[2] > 1 ? name + " x" + item[2].to_s : name
  end

  def self.troop_name(id)
    names = $data_troops[id].members.map { |m| $data_enemies[m.enemy_id].name }
    names.uniq.join(", ")
  end

  def self.write_spoiler(r)
    Dir.mkdir(DIR) unless File.directory?(DIR)
    lines = ["BLACK SOULS randomizer spoiler", "Version " + (r[:version] || "unknown"), "Seed " + seed_text(r[:seed]), ""]
    OPTIONS.each { |o| lines << o[1] + ": " + (r[:opts][o[0]] ? "on" : "off") }
    lines << "" << "[Princess rooms]"
    r[:rooms].each_with_index do |who, room|
      lines << RandoData::PRINCESSES[room][:name] + "'s room: " + RandoData::PRINCESSES[who][:name]
    end
    lines << "" << "[Companions]"
    r[:persona].each { |slot, who| lines << "Where you meet " + $data_actors[slot].name + ": " + $data_actors[who].name }
    lines << "" << "[Fights]"
    r[:swaps].keys.sort.each do |t|
      next if r[:swaps][t][0] == t
      lines << troop_name(t % SLOT_FIGHT_BASE) + " -> " + troop_name(r[:swaps][t][0])
    end
    lines << "" << "[Boss drops]"
    (r[:drops] || []).each do |row|
      next unless RandoData::DROPS.any? { |d| d[0] == row[0] && d[1] == row[1] && d[5] == 1 }
      lines << $data_enemies[row[0]].name + ": " + item_name([row[2], row[3], 1])
    end
    lines << "" << "[Loot]"
    r[:spoiler].each { |row| lines << row[0] + ": " + item_name(row[1]) }
    File.open(DIR + "/spoiler_" + seed_text(r[:seed]) + ".txt", "wb") { |f| f.write(lines.join("\r\n") + "\r\n") }
  rescue StandardError
    nil
  end
end

class Game_System
  attr_accessor :rando
end

class Game_Temp
  attr_accessor :rando_scale, :rando_slot, :rando_look
end

class Game_Switches
  alias rando_set []=
  def []=(switch_id, value)
    rando_set(switch_id, value)
    Rando.behemoth_route_set if switch_id == Rando::BEHEMOTH_ROUTE_SWITCH && value
    Rando.reset_recruits if switch_id == Rando::NEW_GAME_PLUS_SWITCH && !value
  end
end

module DataManager
  class << self
    alias rando_setup_new_game setup_new_game
    def setup_new_game
      @rando_new_game = true
      rando_setup_new_game
    end

    alias rando_create_game_objects create_game_objects
    def create_game_objects
      rando_create_game_objects
      return unless @rando_new_game
      @rando_new_game = false
      if Rando.settings[:enabled]
        Rando.save_settings
        $game_system.rando = Rando.roll(Rando.settings)
        Rando.write_spoiler($game_system.rando)
      end
      Rando.apply_data
    end

    alias rando_extract_save_contents extract_save_contents
    def extract_save_contents(contents)
      rando_extract_save_contents(contents)
      Rando.apply_data
    end
  end
end

class Game_Map
  alias rando_setup_events setup_events
  def setup_events
    Rando.prepare_map(@map, @map_id)
    rando_setup_events
  end
end

class Game_Interpreter
  def rando_key
    return nil if @event_id.nil? || @event_id <= 0 || @map_id != $game_map.map_id
    ev = $game_map.events[@event_id]
    return nil unless ev
    page = ev.rando_rpg_event.pages.index { |pg| pg.list.equal?(@list) }
    return nil unless page
    "#{@map_id}:#{@event_id}:#{page}:#{@index}"
  end

  # returns true when the pickup at this command was replaced
  def rando_grant
    r = Rando.data
    return false unless r && @params[1] == 0 && @params[2] == 0
    key = rando_key
    item = key && r[:place][key]
    return false unless item
    saved = @params
    @params = item[0] == 0 ? [item[1], 0, 0, item[2]] : [item[1], 0, 0, item[2], false]
    begin
      case item[0]
      when 0 then rando_command_126
      when 1 then rando_command_127
      when 2 then rando_command_128
      end
    ensure
      @params = saved
    end
    true
  end

  alias rando_command_126 command_126
  def command_126
    return true if rando_grant
    return true if @params[0] == Rando::BEAUTY_BOOK && @params[1] == 0 && Rando.beauty_away? &&
                   Rando::BEAUTY_BOOK_EVENTS.include?([@map_id, @event_id])
    rando_command_126
  end

  alias rando_command_127 command_127
  def command_127
    return true if rando_grant
    rando_command_127
  end

  alias rando_command_128 command_128
  def command_128
    return true if rando_grant
    rando_command_128
  end

  alias rando_command_301 command_301
  def command_301
    return rando_command_301 if $game_party.in_battle
    $game_temp.rando_scale = nil
    $game_temp.rando_slot = nil
    r = Rando.data
    swap = r && @params[0] == 0 ? r[:swaps][@params[1]] : nil
    return rando_command_301 unless swap
    $game_temp.rando_scale = swap
    $game_temp.rando_slot = swap[6] ? nil : @params[1] % Rando::SLOT_FIGHT_BASE
    Rando::SECOND_PHASE_SWITCHES.each { |s| $game_switches[s] = false } if Rando::SECOND_PHASE_TROOPS.include?(swap[0])
    # a moved final boss gets the reset its own room gives it before the fight, so every phase plays
    (RandoData::PHASE_SWITCHES[swap[0]] || []).each { |s| $game_switches[s] = false }
    Rando.dress_battle(@params[1] % Rando::SLOT_FIGHT_BASE, swap[0])
    saved = @params
    @params = saved.dup
    @params[1] = swap[0]
    begin
      rando_command_301
    ensure
      @params = saved
    end
  end
end

class Game_Event
  def rando_rpg_event
    @event
  end
end

class Game_Player
  alias rando_make_encounter_troop_id make_encounter_troop_id
  def make_encounter_troop_id
    troop_id = rando_make_encounter_troop_id
    $game_temp.rando_scale = nil
    $game_temp.rando_slot = nil
    r = Rando.data
    swap = r && r[:swaps][troop_id]
    return troop_id unless swap
    $game_temp.rando_scale = swap
    $game_temp.rando_slot = swap[6] ? nil : troop_id
    swap[0]
  end
end

class Game_Enemy
  alias rando_param_base param_base
  def param_base(param_id)
    value = rando_param_base(param_id)
    scale = $game_temp && $game_temp.rando_scale
    return value unless scale
    case param_id
    when 0 then [(value * scale[1]).to_i, 1].max
    when 2, 4 then [(value * scale[2]).to_i, 1].max
    when 3, 5 then [(value * scale[3]).to_i, 1].max
    when 6 then [(value * scale[4]).to_i, 1].max
    else value
    end
  end

  alias rando_gold gold
  def gold
    value = rando_gold
    scale = $game_temp && $game_temp.rando_scale
    scale ? (value * scale[5]).to_i : value
  end
end

class Game_Troop
  alias rando_make_drop_items make_drop_items
  def make_drop_items
    slot = $game_temp && $game_temp.rando_slot
    scale = $game_temp && $game_temp.rando_scale
    if !slot && scale && scale[6] && scale[0] == Rando::BEAUTY_TROOP && Rando.beauty_away?
      return rando_make_drop_items + [$data_items[Rando::BEAUTY_BOOK]]
    end
    return rando_make_drop_items unless slot
    Rando.slot_drops(slot, members[0] ? members[0].drop_item_rate : 1)
  end
end

class RPG::UsableItem::Damage
  alias rando_eval eval unless method_defined?(:rando_eval)
  def eval(a, b, v)
    value = rando_eval(a, b, v)
    scale = $game_temp && $game_temp.rando_scale
    return value unless scale && a.enemy?
    # skills with a flat damage number ignore the attack stat
    formula =~ /\A\s*\d+\s*\z/ ? value * scale[2] : value
  end
end

module BattleManager
  class << self
    alias rando_battle_end battle_end
    def battle_end(result)
      rando_battle_end(result)
      $game_temp.rando_scale = nil
      $game_temp.rando_slot = nil
      Rando.undress_battle
    end
  end
end

module Rando
  # Dorothy's training counts a win at the scarecrow, the tin man and the lion, whoever fights there
  DOROTHY_PREY = [[169, "scarecrow"], [167, "tin man"], [168, "lion"]]
  DOROTHY_PREY_LINE = /The Scarecrow, Tin Woodman and Lion/
  MESSAGE_WIDTH = 40

  def self.prey_names(troop)
    $data_troops[troop].members.map { |m| $data_enemies[m.enemy_id].name }.uniq
  end

  def self.prey_name(troop)
    prey_names(troop).join(" & ")
  end

  # names each stand in with the shape its spot still shows, broken into lines that fit the window
  def self.dorothy_prey_lines(text)
    r = data
    return nil unless r && text =~ DOROTHY_PREY_LINE
    return nil if DOROTHY_PREY.all? { |t, _| !r[:swaps][t] || r[:swaps][t][0] == t }
    # a name never breaks across lines and carries its own colour in case the message runs onto a second page
    words = []
    DOROTHY_PREY.each_with_index do |(t, shape), i|
      words << "and" if i == 2
      prey_names(r[:swaps][t] ? r[:swaps][t][0] : t).each_with_index do |n, k|
        words << "&" if k > 0
        words << "\\c[2]#{n}\\c[0]"
      end
      words.concat(["as", "the", shape])
      words[-1] += i == 2 ? "." + text[/\.([^.]*)\z/, 1].to_s : (i == 0 ? "," : "")
    end
    lines = [""]
    words.each do |w|
      wide = (lines[-1] + " " + w).gsub(/\\c\[\d+\]/, "").size
      lines << "" if !lines[-1].empty? && wide > MESSAGE_WIDTH - 1
      lines[-1] = lines[-1].empty? ? w : lines[-1] + " " + w
    end
    lines.map { |l| "　" + l }
  end
end

class Game_Message
  alias rando_add add
  def add(text)
    lines = Rando.dorothy_prey_lines(text.to_s)
    return rando_add(text) unless lines
    lines.each { |l| rando_add(l) }
  end
end

# --- title screen -------------------------------------------------------------

class Window_TitleCommand
  # the game's own labels carry leading spaces, the new one lines up by copying them
  def rando_label
    Vocab::new_game[/\A[\s　]*/].to_s + "Randomizer Options"
  end

  alias rando_make_command_list make_command_list
  def make_command_list
    rando_make_command_list
    index = @list.index { |c| c[:symbol] == :continue } || 1
    item = { :name => rando_label, :symbol => :randomizer, :enabled => true, :ext => nil }
    @list.insert(index + 1, item)
  end

  alias rando_window_width window_width
  def window_width
    measure = Bitmap.new(1, 1)
    text = measure.text_size(rando_label).width
    measure.dispose
    [rando_window_width, text + 8 + standard_padding * 2 + 8].max
  end
end

class Scene_Title
  alias rando_create_command_window create_command_window
  def create_command_window
    rando_create_command_window
    @command_window.set_handler(:randomizer, method(:command_randomizer))
    rando_create_version
  end

  def rando_create_version
    @rando_version = Sprite.new
    @rando_version.bitmap = Bitmap.new(240, 24)
    @rando_version.bitmap.font.size = 18
    @rando_version.bitmap.draw_text(0, 0, 240, 24, "Randomizer v" + Rando::VERSION, 2)
    @rando_version.x = Graphics.width - 248
    @rando_version.y = Graphics.height - 28
    @rando_version.z = 200
  end

  alias rando_terminate terminate
  def terminate
    rando_terminate
    return unless @rando_version
    @rando_version.bitmap.dispose
    @rando_version.dispose
  end

  def command_randomizer
    close_command_window
    SceneManager.goto(Scene_RandoSetup)
  end
end

class Window_RandoOptions < Window_Command
  def initialize
    super((Graphics.width - window_width) / 2, 24)
    self.openness = 255
    activate
    select(0)
  end

  def window_width
    460
  end

  def make_command_list
    add_command("Seed", :seed)
    add_command("New random seed", :reroll)
    Rando::OPTIONS.each { |o| add_command(o[1], :option, true, o[0]) }
    add_command("Done", :done)
  end

  def draw_item(index)
    change_color(normal_color)
    rect = item_rect_for_text(index)
    draw_text(rect, command_name(index))
    case @list[index][:symbol]
    when :seed
      draw_text(rect, Rando.seed_text(Rando.settings[:seed]), 2)
    when :option
      on = Rando.settings[@list[index][:ext]]
      change_color(on ? power_up_color : power_down_color)
      draw_text(rect, on ? "ON" : "OFF", 2)
    end
  end

  # every row fits above the help box, the list scrolls when there are more
  def window_height
    [fitting_height(item_max), Graphics.height - 24 - fitting_height(2)].min
  end

  # the argument is true only on the first frame of a press, holding must not flip it back and forth
  def cursor_right(wrap = false)
    toggle_current if wrap
  end

  def cursor_left(wrap = false)
    toggle_current if wrap
  end

  def toggle_current
    call_handler(:option) if current_symbol == :option
  end

  def description
    case current_symbol
    when :seed then "The same seed and options always make the same world. Press confirm to edit."
    when :reroll then "Picks a new seed."
    when :done then "Saves these settings. They apply to your next New Game. Saves keep their own world."
    else Rando::OPTIONS.find { |o| o[0] == current_ext }[2]
    end
  end
end

class Window_RandoSeed < Window_Base
  DIGITS = 8
  VK_TOP = 0x30
  VK_PAD = 0x60

  def initialize
    super((Graphics.width - 300) / 2, 170, 300, 96)
    self.openness = 0
    @key_state = Win32API.new("user32", "GetAsyncKeyState", "i", "i") rescue nil
    @held = {}
  end

  def start(seed)
    @text = Rando.seed_text(seed).split("")
    @pos = 0
    refresh
    open
  end

  def value
    @text.join.to_i
  end

  def update_input
    if Input.repeat?(:LEFT)
      @pos = (@pos - 1) % DIGITS
      moved
    elsif Input.repeat?(:RIGHT)
      @pos = (@pos + 1) % DIGITS
      moved
    elsif Input.repeat?(:UP)
      change_digit(1)
    elsif Input.repeat?(:DOWN)
      change_digit(-1)
    else
      typed = typed_digit
      if typed
        @text[@pos] = typed.to_s
        @pos = (@pos + 1) % DIGITS
        moved
      end
    end
  end

  def typed_digit
    return nil unless @key_state
    found = nil
    10.times do |d|
      down = @key_state.call(VK_TOP + d) & 0x8000 != 0 || @key_state.call(VK_PAD + d) & 0x8000 != 0
      found = d if down && !@held[d]
      @held[d] = down
    end
    found
  end

  def change_digit(by)
    @text[@pos] = ((@text[@pos].to_i + by) % 10).to_s
    moved
  end

  def moved
    Sound.play_cursor
    refresh
  end

  def refresh
    contents.clear
    draw_text(0, 0, contents.width, line_height, "Type or use the arrows", 1)
    cell = 24
    left = (contents.width - cell * DIGITS) / 2
    DIGITS.times do |i|
      change_color(i == @pos ? power_up_color : normal_color)
      draw_text(left + cell * i, line_height, cell, line_height, @text[i], 1)
    end
    change_color(normal_color)
    contents.fill_rect(left + cell * @pos + 2, line_height * 2 - 2, cell - 4, 2, normal_color)
  end
end

class Scene_RandoSetup < Scene_Base
  def start
    super
    @background = Sprite.new
    @background.bitmap = SceneManager.background_bitmap
    @background.color.set(16, 16, 16, 128)
    @list = Window_RandoOptions.new
    @list.set_handler(:seed, method(:edit_seed))
    @list.set_handler(:reroll, method(:reroll))
    @list.set_handler(:option, method(:toggle))
    @list.set_handler(:done, method(:finish))
    @list.set_handler(:cancel, method(:finish))
    @help = Window_Help.new(2)
    @help.y = Graphics.height - @help.height
    @seed = Window_RandoSeed.new
    @editing = false
  end

  def terminate
    super
    @background.dispose
  end

  def update
    super
    if @editing
      update_seed
    else
      @help.set_text(Rando.wrap(@list.description, 54))
    end
  end

  def edit_seed
    @editing = true
    @seed.start(Rando.settings[:seed])
    @list.deactivate
    @help.set_text(Rando.wrap("Confirm to keep the new seed, cancel to go back.", 54))
  end

  def update_seed
    return unless @seed.open?
    if Input.trigger?(:C)
      Sound.play_ok
      Rando.settings[:seed] = @seed.value
      end_seed
    elsif Input.trigger?(:B)
      Sound.play_cancel
      end_seed
    else
      @seed.update_input
    end
  end

  def end_seed
    @editing = false
    @seed.close
    @list.refresh
    @list.activate
  end

  def reroll
    Rando.settings[:seed] = Rando.fresh_seed
    @list.refresh
    @list.activate
  end

  def toggle
    key = @list.current_ext
    Rando.settings[key] = !Rando.settings[key]
    Sound.play_cursor
    @list.refresh
    @list.activate
  end

  def finish
    Rando.save_settings
    SceneManager.goto(Scene_Title)
  end
end
