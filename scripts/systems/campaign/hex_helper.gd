class_name HexHelper

# Hex math utilities for odd-q offset coordinates (Godot TileMapLayer default)

const DIRECTIONS_EVEN := [
	Vector2i(+1,  0), Vector2i(+1, -1), Vector2i( 0, -1),
	Vector2i(-1,  0), Vector2i(-1, -1), Vector2i( 0, +1),
]
const DIRECTIONS_ODD := [
	Vector2i(+1, +1), Vector2i(+1,  0), Vector2i( 0, -1),
	Vector2i(-1,  0), Vector2i(-1, +1), Vector2i( 0, +1),
]

static func offset_to_cube(col: int, row: int) -> Vector3i:
	var x := col
	var z := row - (col - (col & 1)) / 2
	var y := -x - z
	return Vector3i(x, y, z)

static func cube_to_offset(cube: Vector3i) -> Vector2i:
	var col := cube.x
	var row := cube.z + (cube.x - (cube.x & 1)) / 2
	return Vector2i(col, row)

static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac := offset_to_cube(a.x, a.y)
	var bc := offset_to_cube(b.x, b.y)
	return (absi(ac.x - bc.x) + absi(ac.y - bc.y) + absi(ac.z - bc.z)) / 2

static func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var dirs: Array
	if coord.x & 1 == 0:
		dirs = DIRECTIONS_EVEN
	else:
		dirs = DIRECTIONS_ODD
	var result: Array[Vector2i] = []
	for d in dirs:
		result.append(coord + d)
	return result

static func is_valid(coord: Vector2i, width: int, height: int) -> bool:
	return coord.x >= 0 and coord.x < width and coord.y >= 0 and coord.y < height
