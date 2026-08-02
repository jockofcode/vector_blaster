# Vector Blaster

An Asteroids-style outline shooter — ship, shots, and rocks are all drawn as `draw_line`
polygons, no sprites — built with [Spinel](https://github.com/matz/spinel) and
[sdl](https://github.com/jockofcode/sdl) as a demo of the sdl bindings.

## Requirements

- Spinel (`spin`)
- SDL3, statically linked via the `sdl` package — no `brew install` needed at build or run time

## Install Spinel

With `asdf`:

```bash
asdf plugin add spinel https://github.com/jockofcode/asdf-spinel
asdf install spinel master
asdf set -u spinel master   # make it the default (~/.tool-versions)
```

Or build it from source:

```bash
git clone https://github.com/matz/spinel.git
cd spinel
make
export PATH="$PWD/bin:$PATH"
cd -
```

## Play

```sh
spin run vector_blaster
```

Or build first and run the binary directly:

```sh
spin build
./build/bin/vector_blaster
```

## Controls

| Key | Action |
|---|---|
| Left / Right | Rotate ship |
| Up | Thrust |
| Space | Fire |
| W | Warp to the spot on screen with the most open room around it |
| R | Restart (after game over) |
| Esc | Quit |
