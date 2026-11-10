extends RefCounted
## Чистые функции пути: A* по тайловой сетке (8 направлений, без срезания углов)
## + сглаживание пути «натягиванием верёвки» (LOS). Никакого состояния.
## walkable — Callable(Vector2i) -> bool.

static func astar(walkable: Callable, w: int, h: int, start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return []
	goal = _clamp_free(walkable, w, h, goal)
	start = _clamp_free(walkable, w, h, start)
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1) or start == goal:
		return []
	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var open: Array = [start]
	var g := {start: 0.0}
	var came := {}
	var closed := {}
	var guard := 0
	while not open.is_empty() and guard < 40000:
		guard += 1
		var bi := 0
		var bf: float = g[open[0]] + _octile(open[0], goal)
		for i in range(1, open.size()):
			var f: float = g[open[i]] + _octile(open[i], goal)
			if f < bf:
				bf = f
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == goal:
			return _unwind(came, goal)
		closed[cur] = true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			if closed.has(nxt) or not walkable.call(nxt):
				continue
			if d.x != 0 and d.y != 0:  # без срезания углов
				if not walkable.call(Vector2i(nxt.x, cur.y)) or not walkable.call(Vector2i(cur.x, nxt.y)):
					continue
			var step: float = 1.4142 if (d.x != 0 and d.y != 0) else 1.0
			var ng: float = g[cur] + step
			if g.has(nxt) and ng >= g[nxt]:
				continue
			g[nxt] = ng
			came[nxt] = cur
			if not open.has(nxt):
				open.append(nxt)
	return []  # недостижимо

## LOS-сглаживание: убирает «лесенку» тайлов, оставляя диагонали и повороты.
static func simplify(path: Array, walkable: Callable) -> Array:
	if path.size() <= 2:
		return path.duplicate()
	var out: Array = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1 and not los(path[i], path[j], walkable):
			j -= 1
		out.append(path[j])
		i = j
	return out

## Прямая видимость между тайлами: все клетки вдоль линии проходимы.
static func los(a: Vector2i, b: Vector2i, walkable: Callable) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 4
	if steps <= 0:
		return true
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var c := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
		if not walkable.call(c):
			return false
	return true

static func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.4142 * float(mini(dx, dy))

static func _unwind(came: Dictionary, goal: Vector2i) -> Array:
	var out: Array = [goal]
	var cur := goal
	while came.has(cur):
		cur = came[cur]
		out.append(cur)
	out.reverse()
	out.pop_front()  # стартовая клетка не нужна
	return out

## Тайл в границах и проходим; иначе — ближайший свободный (кольцами), или (-1,-1).
static func _clamp_free(walkable: Callable, w: int, h: int, t: Vector2i) -> Vector2i:
	var inside := t.x >= 0 and t.y >= 0 and t.x < w and t.y < h
	if inside and walkable.call(t):
		return t
	var cx := clampi(t.x, 0, w - 1)
	var cy := clampi(t.y, 0, h - 1)
	if walkable.call(Vector2i(cx, cy)):
		return Vector2i(cx, cy)
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := Vector2i(cx + dx, cy + dy)
				if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and walkable.call(c):
					return c
	return Vector2i(-1, -1)
