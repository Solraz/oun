extends Node
class_name DebugFunctions

func debounced(fn: Callable, debounce_sec: float) -> Callable:
	# is array because they are passed by reference
	# (it's hacky, I know)
	var last_call_usec: PackedInt64Array = [-1.0]

	return func():
		if last_call_usec[0] == -1.0 or (Time.get_ticks_usec() - last_call_usec[0]) * 1e-6 > debounce_sec:
			last_call_usec[0] = Time.get_ticks_usec()
			fn.call()
