class_name Difficulty

# Easy or hard, picked on the start screen. Static, so it's remembered when
# the level reloads (Play again)

const EASY := "easy"
const HARD := "hard"

const ENEMY_SHARE := {EASY: 0.6, HARD: 1.0} # Share of the level's enemies that are kept
const DAMAGE_MULTIPLIER := {EASY: 0.5, HARD: 1.5} # Damage the player takes from enemies

static var level := "" # Empty until the player picks one

static func chosen() -> bool:
	return level != ""

static func display_name() -> String:
	return level.capitalize()

static func enemy_share() -> float:
	return ENEMY_SHARE.get(level, 1.0)

static func damage_multiplier() -> float:
	return DAMAGE_MULTIPLIER.get(level, 1.0)
