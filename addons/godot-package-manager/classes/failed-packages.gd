class FailedPackages:
	var failed_package_log := [] # Log of failed packages and reasons
	var failed_packages := [] # Array of failed package names only

	func add(package_name: String, reason: String) -> void:
		failed_package_log.append("%s - %s" % [package_name, reason])
		failed_packages.append(package_name)

	func get_logs() -> String:
		failed_package_log.invert()
		return PoolStringArray(failed_package_log).join("\n")

	func has_logs() -> bool:
		return not failed_package_log.empty()
	
	func get_failed_packages() -> Array:
		return failed_packages.duplicate()