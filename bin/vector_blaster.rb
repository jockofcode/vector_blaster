require "sdl"

SDL::Log.open("/tmp/sdl_vector_blaster.log")

WIDTH  = 800
HEIGHT = 600

TWO_PI = Math::PI * 2.0

SHIP_TURN_SPEED  = 0.08
SHIP_THRUST      = 0.12
SHIP_DRAG        = 0.988
SHIP_MAX_SPEED   = 6.0
SHIP_RADIUS      = 9.0
LIVES_START      = 3
INVULN_FRAMES    = 90

BULLET_SPEED = 8.0
BULLET_LIFE  = 42
FIRE_COOLDOWN = 10

ASTEROID_VERTS   = 10
BASE_RADIUS      = 46.0
MIN_SPLIT_RADIUS = 18.0
BASE_COUNT       = 4

WARP_GRID_STEP = 24.0
WARP_INVULN    = INVULN_FRAMES / 2

R_KEY = "r".ord
W_KEY = "w".ord

def wrap(v, max)
  v += max if v < 0
  v -= max if v >= max
  v
end

def frand
  rand(10_000) / 10_000.0
end

def make_verts
  verts = []
  i = 0
  while i < ASTEROID_VERTS
    verts.push(0.7 + frand * 0.6)
    i += 1
  end
  verts
end

def new_asteroid(x, y, radius)
  angle = frand * TWO_PI
  speed = 0.8 + frand * 1.6
  {
    x:      x,
    y:      y,
    dx:     Math.cos(angle) * speed,
    dy:     Math.sin(angle) * speed,
    radius: radius,
    rotation:  frand * TWO_PI,
    spin_rate: (frand - 0.5) * 0.05,
    verts:  make_verts,
  }
end

# Pushes fragments onto `spawned` rather than directly onto
# state[:asteroids]. This is called from inside check_bullet_hits' loop
# over state[:asteroids] itself; pushing new elements onto that same
# array mid-iteration corrupts it under Spinel (confirmed by an isolated
# repro: a single hit on a lone asteroid left state[:asteroids] with zero
# elements instead of two fresh fragments) even though the identical
# sequence works fine under plain Ruby. Collecting spawns separately and
# merging them into `survivors` only after the loop finishes sidesteps it.
def split_asteroid(state, a, spawned)
  if a[:radius] > MIN_SPLIT_RADIUS
    state[:score] += 20
    new_r = a[:radius] * 0.55
    spawned.push(new_asteroid(a[:x], a[:y], new_r))
    spawned.push(new_asteroid(a[:x], a[:y], new_r))
  else
    state[:score] += 50
  end
end

def spawn_wave(state)
  count = BASE_COUNT + state[:level]
  i = 0
  while i < count
    ax = frand * WIDTH
    ay = frand * HEIGHT
    # keep new asteroids away from screen center where the ship respawns
    if (ax - WIDTH / 2.0).abs < 120 && (ay - HEIGHT / 2.0).abs < 120
      ax = 0.0
    end
    state[:asteroids].push(new_asteroid(ax, ay, BASE_RADIUS))
    i += 1
  end
end

def respawn_ship(state)
  state[:ship] = {
    x: WIDTH / 2.0, y: HEIGHT / 2.0,
    dx: 0.0, dy: 0.0,
    heading: 0.0,
    thrusting: false,
    turn_left: false, turn_right: false,
    invuln: INVULN_FRAMES,
  }
end

# Shortest signed distance from a to b on a wrapped [0, size) axis -- e.g.
# on a 800-wide axis, going from x=10 to x=790 is a delta of -20 (wrap
# left) rather than +780 (the raw difference). The ship and asteroids
# wrap the screen, so "most room around it" needs to measure distance the
# same way the world actually behaves, not as if the edges were walls.
def wrapped_delta(a, b, size)
  d    = b - a
  half = size / 2.0
  d = d + size if d < 0 - half
  d = d - size if d > half
  d
end

# Scans a coarse grid of candidate points and returns the one whose
# closest asteroid (measured wrapped, and net of that asteroid's own
# radius) is as far away as possible -- the spot with the most open room
# around it, not just an arbitrary/random teleport.
def find_warp_spot(asteroids)
  return [WIDTH / 2.0, HEIGHT / 2.0] if asteroids.empty?

  best_x         = WIDTH / 2.0
  best_y         = HEIGHT / 2.0
  best_clearance = 0 - 1.0

  gy = WARP_GRID_STEP / 2.0
  while gy < HEIGHT
    gx = WARP_GRID_STEP / 2.0
    while gx < WIDTH
      clearance = 999_999.0
      asteroids.each do |a|
        dx = wrapped_delta(gx, a[:x], WIDTH.to_f)
        dy = wrapped_delta(gy, a[:y], HEIGHT.to_f)
        d  = Math.sqrt(dx * dx + dy * dy) - a[:radius]
        clearance = d if d < clearance
      end

      if clearance > best_clearance
        best_clearance = clearance
        best_x         = gx
        best_y         = gy
      end

      gx += WARP_GRID_STEP
    end
    gy += WARP_GRID_STEP
  end

  [best_x, best_y]
end

def warp_ship(state)
  spot = find_warp_spot(state[:asteroids])
  ship = state[:ship]
  ship[:x]      = spot[0]
  ship[:y]      = spot[1]
  ship[:dx]     = 0.0
  ship[:dy]     = 0.0
  ship[:invuln] = WARP_INVULN
end

def new_game
  state = {
    asteroids:    [],
    bullets:      [],
    score:        0,
    lives:        LIVES_START,
    level:        1,
    fire_cooldown: 0,
    game_over:    false,
  }
  respawn_ship(state)
  spawn_wave(state)
  state
end

# ---- Updates ----


# Spinel compiler bug: a compound assignment (+=, -=, *=, /=) through a
# Hash local extracted from a parent Hash via `local = outer[:key]` silently
# no-ops -- the write is lost even though a plain `=` assignment through
# the same extracted local correctly aliases the original. Confirmed by an
# isolated repro outside this game: `ship = state[:ship]; ship[:x] -= 1`
# leaves both `ship[:x]` and `state[:ship][:x]` unchanged under `spinel -E`,
# while `ship[:x] = ship[:x] - 1` (same extracted local) works correctly.
# This was silently breaking every line below -- the ship never turned,
# thrusted, dragged, or lost invulnerability, since `ship` here is exactly
# such an extracted local. Fix: explicit `x = x OP y` form throughout.
def update_ship(state)
  ship = state[:ship]

  ship[:heading] = ship[:heading] - SHIP_TURN_SPEED if ship[:turn_left]
  ship[:heading] = ship[:heading] + SHIP_TURN_SPEED if ship[:turn_right]

  if ship[:thrusting]
    ship[:dx] = ship[:dx] + Math.sin(ship[:heading]) * SHIP_THRUST
    ship[:dy] = ship[:dy] - Math.cos(ship[:heading]) * SHIP_THRUST
  end

  ship[:dx] = ship[:dx] * SHIP_DRAG
  ship[:dy] = ship[:dy] * SHIP_DRAG

  speed = Math.sqrt(ship[:dx] * ship[:dx] + ship[:dy] * ship[:dy])
  if speed > SHIP_MAX_SPEED
    scale = SHIP_MAX_SPEED / speed
    ship[:dx] = ship[:dx] * scale
    ship[:dy] = ship[:dy] * scale
  end

  ship[:x] = wrap(ship[:x] + ship[:dx], WIDTH.to_f)
  ship[:y] = wrap(ship[:y] + ship[:dy], HEIGHT.to_f)

  ship[:invuln] = ship[:invuln] - 1 if ship[:invuln] > 0
end

def fire_bullet(state)
  return if state[:fire_cooldown] > 0

  ship = state[:ship]
  state[:bullets].push({
    x:  ship[:x] + Math.sin(ship[:heading]) * SHIP_RADIUS,
    y:  ship[:y] - Math.cos(ship[:heading]) * SHIP_RADIUS,
    dx: Math.sin(ship[:heading]) * BULLET_SPEED,
    dy: 0.0 - Math.cos(ship[:heading]) * BULLET_SPEED,
    life: BULLET_LIFE,
  })
  state[:fire_cooldown] = FIRE_COOLDOWN
end

def update_bullets(state)
  state[:fire_cooldown] -= 1 if state[:fire_cooldown] > 0

  alive = []
  state[:bullets].each do |b|
    b[:x] = wrap(b[:x] + b[:dx], WIDTH.to_f)
    b[:y] = wrap(b[:y] + b[:dy], HEIGHT.to_f)
    b[:life] -= 1
    alive.push(b) if b[:life] > 0
  end
  state[:bullets] = alive
end

def update_asteroids(state)
  state[:asteroids].each do |a|
    a[:x] = wrap(a[:x] + a[:dx], WIDTH.to_f)
    a[:y] = wrap(a[:y] + a[:dy], HEIGHT.to_f)
    a[:rotation] = a[:rotation] + a[:spin_rate]
  end
end

def check_bullet_hits(state)
  hit_bullets    = {}
  hit_asteroids  = {}

  state[:bullets].each_with_index do |b, bi|
    next if hit_bullets[bi]

    state[:asteroids].each_with_index do |a, ai|
      next if hit_asteroids[ai]

      dx = b[:x] - a[:x]
      dy = b[:y] - a[:y]
      if Math.sqrt(dx * dx + dy * dy) < a[:radius]
        hit_bullets[bi]   = true
        hit_asteroids[ai] = true
      end
    end
  end

  return if hit_asteroids.empty?

  survivors = []
  spawned   = []
  state[:asteroids].each_with_index do |a, ai|
    if hit_asteroids[ai]
      split_asteroid(state, a, spawned)
    else
      survivors.push(a)
    end
  end
  spawned.each { |s| survivors.push(s) }
  state[:asteroids] = survivors

  survivors_b = []
  state[:bullets].each_with_index do |b, bi|
    survivors_b.push(b) unless hit_bullets[bi]
  end
  state[:bullets] = survivors_b
end

def check_ship_hit(state)
  ship = state[:ship]
  return if ship[:invuln] > 0

  state[:asteroids].each do |a|
    dx = ship[:x] - a[:x]
    dy = ship[:y] - a[:y]
    if Math.sqrt(dx * dx + dy * dy) < a[:radius] + SHIP_RADIUS
      state[:lives] -= 1
      if state[:lives] <= 0
        state[:game_over] = true
      else
        respawn_ship(state)
      end
      return
    end
  end
end

def update(state)
  return if state[:game_over]

  update_ship(state)
  update_bullets(state)
  update_asteroids(state)
  check_bullet_hits(state)
  check_ship_hit(state)

  if state[:asteroids].empty?
    state[:level] += 1
    spawn_wave(state)
  end
end

# ---- Rendering ----

def draw_ship(renderer, ship)
  return if ship[:invuln] > 0 && ship[:invuln] % 10 < 5

  h  = ship[:heading]
  cx = ship[:x]
  cy = ship[:y]

  # local-space triangle: nose, rear-left, rear-right
  pts = [[0.0, -12.0], [-7.0, 9.0], [7.0, 9.0]]
  world = pts.map do |p|
    lx = p[0]
    ly = p[1]
    rx = lx * Math.cos(h) - ly * Math.sin(h)
    ry = lx * Math.sin(h) + ly * Math.cos(h)
    [(cx + rx).round.to_f, (cy + ry).round.to_f]
  end

  c = SDL::Color::WHITE
  renderer.draw_color(c[0], c[1], c[2], c[3])
  renderer.draw_line(world[0][0], world[0][1], world[1][0], world[1][1])
  renderer.draw_line(world[1][0], world[1][1], world[2][0], world[2][1])
  renderer.draw_line(world[2][0], world[2][1], world[0][0], world[0][1])
end

def draw_asteroid(renderer, a)
  c = SDL::Color::GRAY
  renderer.draw_color(c[0], c[1], c[2], c[3])

  # Spinel compiler bug: the first element of a 2-element array literal
  # pushed via `array.push([a, b])` from inside a `while` loop is corrupted
  # once that push site executes more than once per call; the second
  # element is unaffected. Sidestepped here with two parallel arrays
  # instead of an array of [x, y] pairs.
  n = a[:verts].length
  pts_x = []
  pts_y = []
  i = 0
  while i < n
    angle = a[:rotation] + (i.to_f / n) * TWO_PI
    r     = a[:radius] * a[:verts][i]
    pts_x.push((a[:x] + Math.cos(angle) * r).round.to_f)
    pts_y.push((a[:y] + Math.sin(angle) * r).round.to_f)
    i += 1
  end

  i = 0
  while i < n
    j = (i + 1) % n
    renderer.draw_line(pts_x[i], pts_y[i], pts_x[j], pts_y[j])
    i += 1
  end
end

def draw_bullets(renderer, bullets)
  c = SDL::Color::YELLOW
  renderer.draw_color(c[0], c[1], c[2], c[3])
  bullets.each do |b|
    renderer.fill_rect(b[:x].round - 1, b[:y].round - 1, 2, 2)
  end
end

def draw_hud(renderer, font, state)
  hud = SDL::Color::WHITE
  renderer.draw_text(font, "Score: #{state[:score]}", 12, 8, hud[0], hud[1], hud[2], hud[3])
  renderer.draw_text(font, "Lives: #{state[:lives] > 0 ? state[:lives] : 0}", WIDTH - 130, 8, hud[0], hud[1], hud[2], hud[3])
  renderer.draw_text(font, "Level: #{state[:level]}", WIDTH / 2 - 50, 8, hud[0], hud[1], hud[2], hud[3])

  if state[:game_over]
    warn = SDL::Color::RED
    renderer.draw_text(font, "GAME OVER", WIDTH / 2 - 70, HEIGHT / 2 - 30, warn[0], warn[1], warn[2], warn[3])
    renderer.draw_text(font, "R to restart", WIDTH / 2 - 70, HEIGHT / 2, hud[0], hud[1], hud[2], hud[3])
  else
    help = SDL::Color::GRAY
    renderer.draw_text(font, "Left/Right: rotate   Up: thrust   Space: fire   W: warp   Esc: quit", 12, HEIGHT - 28, help[0], help[1], help[2], help[3])
  end
end

def render(renderer, font, state)
  renderer.draw_color(4, 4, 12, 255)
  renderer.clear

  state[:asteroids].each { |a| draw_asteroid(renderer, a) }
  draw_bullets(renderer, state[:bullets])
  draw_ship(renderer, state[:ship]) unless state[:game_over]
  draw_hud(renderer, font, state)

  renderer.present
end

# ---- Main loop ----

SDL::Screen.open("Vector Blaster", width: WIDTH, height: HEIGHT) do |window, renderer|
  window.title = "Vector Blaster"

  font    = SDL::Font.bundled(SDL::Fonts::VT323_NAME, 24)
  state   = new_game
  running = true

  while running
    while (event_type = SDL::Event.poll)
      if event_type == LibSDL::QUIT
        running = false
      elsif event_type == LibSDL::KEYDOWN
        key = SDL::Event.key_sym

        if key == LibSDL::K_ESCAPE
          running = false
        elsif state[:game_over]
          state = new_game if key == R_KEY
        elsif key == LibSDL::K_LEFT
          state[:ship][:turn_left] = true
        elsif key == LibSDL::K_RIGHT
          state[:ship][:turn_right] = true
        elsif key == LibSDL::K_UP
          state[:ship][:thrusting] = true
        elsif key == LibSDL::K_SPACE
          fire_bullet(state)
        elsif key == W_KEY
          warp_ship(state)
        end
      elsif event_type == LibSDL::KEYUP
        key = SDL::Event.key_sym
        unless state[:game_over]
          state[:ship][:turn_left]  = false if key == LibSDL::K_LEFT
          state[:ship][:turn_right] = false if key == LibSDL::K_RIGHT
          state[:ship][:thrusting]  = false if key == LibSDL::K_UP
        end
      end
    end

    update(state)
    render(renderer, font, state)
    SDL::Screen.delay(16)
  end

  font.close
end
