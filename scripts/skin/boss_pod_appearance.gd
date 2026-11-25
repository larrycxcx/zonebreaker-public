class_name BossPodAppearance
extends BossSkullAppearance
## The look of stage 5's boss, the "biopod": laser, charge and one-shot clips (one per cannon) are all the skull's,
## plus a **shell** — while gameplay says it is shelled, the round-shell frames loop (`shell`); how long is up to gameplay.
## The placeholder blocks have no `show_shell()`, so with the default skin nothing is drawn and the rules do not change.

var _shell := false


func show_shell(on: bool) -> void:
	if on == _shell:
		return
	_shell = on
	_refresh()


func is_shelled() -> bool:
	return _shell


func clip() -> StringName:
	if _shell and not _dead:
		return &"shell"
	return super()
