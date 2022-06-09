class_name GPM
extends Reference

## A message that may be logged at any point during runtime
signal message_logged(text)

## Signifies the start of a package operation
signal operation_started(op_name, num_packages)
## Emitted when a package has started processing
signal operation_checkpoint_reached(package_name)
## Emitted when the package operation is complete
signal operation_finished()

const ADDONS_DIR_CACHE := "res://addons/.cache/"

const ADDONS_DIR_FORMAT := "res://addons/%s"
const ADDONS_DIR_FORMAT_CACHE := "res://addons/.cache/%s"


const DryRunValues := {
	"OK": "ok",
	"UPDATE": "packages_to_update",
	"INVALID": "packages_with_errors"
}

const PACKAGE_FILE := "godot.package"
const PackageKeys := {
	"PACKAGES": "packages",
	"HOOKS": "hooks",
	"VERSION": "version",
	"SCRIPTS": "scripts",
	"REQUIRED_WHEN": "required_when",
	"OPTIONAL_WHEN": "optional_when"
}
const LOCK_FILE := "godot.lock"
const LockFileKeys := {
	"VERSION": "version",
	"INTEGRITY": "integrity"
}

const NpmManifestKeys := {
	"VERSION": "version",
	"DIST": "dist",
	"INTEGRITY": "integrity",
	"TARBALL": "tarball"
}

const ValidHooks := {
	"PRE_DRY_RUN": "pre_dry_run",
	"POST_DRY_RUN": "post_dry_run",

	"PRE_UPDATE": "pre_update",
	"POST_UPDATE": "post_update",
	
	"PRE_PURGE": "pre_purge",
	"POST_PURGE": "post_purge"
}

#endregion

###############################################################################
# Builtin functions                                                           #
###############################################################################

###############################################################################
# Connections                                                                 #
###############################################################################

###############################################################################
# Private functions                                                           #
###############################################################################

## Reads all relevant config files
## Empty or missing configs are not considered errors
##
## @return: GPMResult<Tuple<Dictionary, Dictionary>> - A tuple-like structure containing the relevant files
static func _read_all_configs() -> GPMResult:
	var package_file := {}

	var res := read_config(PACKAGE_FILE)
	if res.is_ok():
		package_file = res.unwrap()

	var lock_file := {}
	
	res = read_config(LOCK_FILE)
	if res.is_ok():
		lock_file = res.unwrap()

	return GPMUtils.OK([package_file, lock_file])

static func _is_valid_new_package(lock_file: Dictionary, package_name, version: String, integrity: String = "_MISSING_") -> bool:
	
	if lock_file.has(package_name):
		if lock_file.get(LockFileKeys.VERSION, "") == version:
			return false

		if integrity != "_MISSING_":
			if lock_file.get(LockFileKeys.INTEGRITY, "") == integrity:
				return false

	return true

#region Scripts

static func _clean_text(text: String) -> GPMResult:
	var whitespace_regex := RegEx.new()
	whitespace_regex.compile("\\B(\\s+)\\b")

	var r := PoolStringArray()

	var split: PoolStringArray = text.split("\n")
	if split.empty():
		return GPMUtils.ERR(GPMError.Code.MISSING_SCRIPT)
	
	var first_line := ""
	for i in split:
		first_line = i
		if not first_line.strip_edges().empty():
			break

	# The first line should not have any tabs at all, so any tabs there can be assumed
	# to also be uniformly applied to the other lines
	# It's also possible spaces are used instead of tabs, so check for spaces as well
	var regex_match := whitespace_regex.search(first_line)
	if regex_match == null:
		return GPMUtils.OK(split)

	var empty_prefix: String = regex_match.get_string()

	for i in split:
		# We can guarantee that the string will always be empty and, after the first iteration,
		# will always have a proper new line character
		r.append(i.trim_prefix(empty_prefix))

	return GPMUtils.OK(r)

## Build a script from a `String`
##
## @param: text: String - The code to build and compile
##
## @return: GPMResult<GPMAdvancedExpression> - The compiled script
static func _build_script(text: String) -> GPMResult:
	var ae := GPMAdvancedExpression.new()

	var clean_res := _clean_text(text)
	if clean_res.is_err():
		return clean_res

	var split: PoolStringArray = clean_res.unwrap()

	ae.runner.add_param("gpm")

	for line in split:
		ae.add(line)

	if ae.compile() != OK:
		return GPMUtils.ERR(GPMError.Code.SCRIPT_COMPILE_FAILURE, "_build_script")

	return GPMUtils.OK(ae)

## Parse all hooks. Failures cause the entire function to short-circuit
##
## @param: data: Dictionary - The entire package dictionary
##
## @return: GPMResult<GPMHooks> - The result of the operation
static func _parse_hooks(data: Dictionary) -> GPMResult:
	var hooks := GPMHooks.new()

	var file_hooks: Dictionary = data.get(PackageKeys.HOOKS, {})

	for key in file_hooks.keys():
		if not key in ValidHooks.values():
			printerr("Unrecognized hook %s" % key)
			continue

		var val = file_hooks[key]
		match typeof(val):
			TYPE_ARRAY:
				var res = _build_script(PoolStringArray(val).join("\n"))
				if res.is_err():
					return GPMUtils.ERR(GPMError.Code.SCRIPT_COMPILE_FAILURE, key)
				hooks.add(key, res.unwrap())
			TYPE_DICTIONARY:
				var type = val.get("type", "")
				var value = val.get("value", "")
				if type == "script":
					var res = _build_script(value)
					if res.is_err():
						return GPMUtils.ERR(GPMError.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				elif type == "script_name":
					if not data[PackageKeys.SCRIPTS].has(value):
						return GPMUtils.ERR(GPMError.Code.MISSING_SCRIPT, key)
					
					var res = _build_script(data[PackageKeys.SCRIPTS][value])
					if res.is_err():
						return GPMUtils.ERR(GPMError.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				else:
					return GPMUtils.ERR(GPMError.Code.BAD_SCRIPT_TYPE, value)
			_:
				var res = _build_script(val)
				if res.is_err():
					return GPMUtils.ERR(GPMError.Code.SCRIPT_COMPILE_FAILURE, key)
				hooks.add(key, res.unwrap())

	return GPMUtils.OK(hooks)

## Create list of packages to be updated
##
## @param: data: Dictionary - The entire package dictionary
##
## @return: GPMResult<> - The result of the operation

func list_packages_to_update(package_file, failed_packages: GPMFailedPackages) -> Dictionary:
	var update_packages := {}

	for package_name in package_file.get(PackageKeys.PACKAGES, {}).keys():
		emit_signal("operation_checkpoint_reached", package_name)

		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()
		var cache_dir: String = ADDONS_DIR_FORMAT_CACHE % package_name.get_file()

		var data = package_file[PackageKeys.PACKAGES][package_name]
		var res

		if data is Dictionary:
			
			# TODO: Implement version check

			# package_version = data.get(PackageKeys.VERSION, "")
			# if package_version.empty():
			# 	failed_packages.add_response(package_name, res)
			# 	continue
			
			# Keep track of whether we should skip to the next item
			# Used to break out of inner for-loop and continue to next item
			# in outer for-loop
			var should_skip := false
			for n in [PackageKeys.REQUIRED_WHEN, PackageKeys.OPTIONAL_WHEN]:
				if data.has(n):
					var body
					var body_data = data[n]
					if body_data is Dictionary:
						var type = body_data.get("type", "")
						var value = body_data.get("value", "")
						if type == "script":
							body = value
						elif type == "script_name":
							if not package_file[PackageKeys.SCRIPTS].has(value):
								failed_packages.add_response(package_name, "Script does not exist %s" % value)
								should_skip = true
								break

							body = package_file[PackageKeys.SCRIPTS][value]
						else:
							# Invalid type, assume the entire block is bad
							failed_packages.add_response(package_name, "Invalid type %s, bailing out" % type)
							should_skip = true
							break
					else:
						body = body_data
					res = _build_script(body if body is String else PoolStringArray(body).join("\n"))
					if res.is_err():
						failed_packages.add_response(package_name, "Failed to parse section %s" % n)
						should_skip = true
						break
					
					var execute_value = res.unwrap().execute([self])
					if typeof(execute_value) == TYPE_BOOL:
						match n:
							PackageKeys.REQUIRED_WHEN:
								if execute_value == false:
									emit_signal("message_logged", "Skipping package %s because of %s condition" %
											[package_name, n])
									should_skip = true
							PackageKeys.OPTIONAL_WHEN:
								if execute_value == true:
									emit_signal("message_logged", "Skipping package %s because of %s condition" %
											[package_name, n])
									should_skip = true

					if should_skip:
						break
			if should_skip:
				continue
		else:
			data = {
				"version": data,
				"src": "npm",
			}

		update_packages[package_name] = data

	return update_packages

## Processes github packages. Failures cause the entire function to short-circuit
##
## @param: data: Dictionary - The entire package dictionary
##
## @return: GPMResult<GPMHooks> - The result of the operation
static func _process_github(data: Dictionary) -> GPMResult:
	return GPMUtils.OK()

## Processes npm packages. Failures cause the entire function to short-circuit
##
## @param: data: Dictionary - The entire package dictionary
##
## @return: GPMResult<GPMHooks> - The result of the operation
static func _process_npm(data: Dictionary) -> GPMResult:
	return GPMUtils.OK()

#endregion

###############################################################################
# Public functions                                                            #
###############################################################################

#region Config handling

## Reads a config file
##
## @param: file_name: String - Either the PACKAGE_FILE or the LOCK_FILE
##
## @return: GPMResult<Dictionary> - The contents of the config file
static func read_config(file_name: String) -> GPMResult:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return GPMUtils.ERR(GPMError.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.READ) != OK:
		return GPMUtils.ERR(GPMError.Code.FILE_OPEN_FAILURE, file_name)

	var parse_result := JSON.parse(file.get_as_text())
	if parse_result.error != OK:
		return GPMUtils.ERR(GPMError.Code.PARSE_FAILURE, file_name)

	# Closing to save on memory I guess
	file.close()

	var data = parse_result.result
	if not data is Dictionary:
		return GPMUtils.ERR(GPMError.Code.UNEXPECTED_DATA, file_name)

	if file_name == PACKAGE_FILE and data.get(PackageKeys.PACKAGES, {}).empty():
		return GPMUtils.ERR(GPMError.Code.NO_PACKAGES, file_name)

	return GPMUtils.OK(data)

## Writes a `Dictionary` to a specified file_name in the project root
##
## @param: file_name: String - Either the `PACKAGE_FILE` or the `LOCK_FILE`
##
## @result: GPMResult<()> - The result of the operation
static func write_config(file_name: String, data: Dictionary) -> GPMResult:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return GPMUtils.ERR(GPMError.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.WRITE) != OK:
		return GPMUtils.ERR(GPMError.Code.FILE_OPEN_FAILURE, file_name)

	file.store_string(JSON.print(data, "\t"))

	file.close()

	return GPMUtils.OK()

#endregion

## WARNING: This function is not working now!
## Reads the config files and returns the operation that would have been taken for each package.
##
## @return: GPMResult<Dictionary> - The actions that would have been taken or OK
func dry_run() -> GPMResult:
	var res := _read_all_configs()
	if not res:
		return GPMUtils.ERR(GPMError.Code.GENERIC, "Unable to read configs, bailing out")
	if res.is_err():
		return res

	var configs: Array = res.unwrap()

	var package_file: Dictionary = configs[0]
	var lock_file: Dictionary = configs[1]

	res = _parse_hooks(package_file)
	if res.is_err():
		return res

	var hooks: GPMHooks = res.unwrap()
	var pre_dry_run_res = hooks.run(self, ValidHooks.PRE_DRY_RUN)
	if typeof(pre_dry_run_res) == TYPE_BOOL and pre_dry_run_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_DRY_RUN)
		return GPMUtils.OK({DryRunValues.OK: true})

	var dir := Directory.new()

	emit_signal("operation_started", "dry run", package_file[PackageKeys.PACKAGES].size())
	
	var failed_packages := GPMFailedPackages.new()
	var packages_to_update := []
	for package_name in package_file.get(PackageKeys.PACKAGES, {}).keys():
		emit_signal("operation_checkpoint_reached", package_name)
		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()
		var package_version := ""

		var data = package_file[PackageKeys.PACKAGES][package_name]
		if data is Dictionary:
			package_version = data.get(PackageKeys.VERSION, "")
			if package_version.empty():
				failed_packages.add(package_name, res.unwrap_err().to_string())
				continue
			# TODO handle `required_when` and `optional_when` here
		else:
			package_version = data

		res = yield(GPMNpm.request_npm_manifest(package_name, package_version), "completed")
		if not res or res.is_err():
			failed_packages.add(package_name, res.unwrap_err().to_string() if res else GPMUtils.DEFAULT_ERROR)
			continue

		var npm_manifest: Dictionary = res.unwrap()
		var npm_version = npm_manifest.get(NpmManifestKeys.VERSION, "__MISSING__")
		var npm_integrity = npm_manifest.get(NpmManifestKeys.DIST, {}).get(NpmManifestKeys.INTEGRITY, "__MISSING__")
		
		if dir.dir_exists(dir_name):
			if not _is_valid_new_package(lock_file, package_name, npm_version, npm_integrity):
				continue
			packages_to_update.append(package_name)
	
	emit_signal("operation_finished")

	var post_dry_run_res = hooks.run(self, ValidHooks.POST_DRY_RUN)
	if typeof(post_dry_run_res) == TYPE_BOOL and post_dry_run_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_DRY_RUN)
		return GPMUtils.OK({DryRunValues.OK: true})

	return GPMUtils.OK({
		DryRunValues.OK: packages_to_update.empty() and failed_packages.failed_package_log.empty(),
		DryRunValues.UPDATE: packages_to_update,
		DryRunValues.INVALID: failed_packages.failed_package_log
	})

## Reads the `godot.package` file and updates all packages. A `godot.lock` file is also written afterwards.
##
## @result: GPMResult<()> - The result of the operation
func update(force: bool = false) -> GPMResult:
	var res := _read_all_configs()
	if not res:
		return GPMUtils.ERR(GPMError.Code.GENERIC, "Unable to read configs, bailing out")
	if res.is_err():
		return res

	var configs: Array = res.unwrap()

	var package_file: Dictionary = configs[0]
	var lock_file: Dictionary = configs[1]

	res = _parse_hooks(package_file)
	if res.is_err():
		return res

	var hooks: GPMHooks = res.unwrap()
	var pre_update_res = hooks.run(self, ValidHooks.PRE_UPDATE)
	if typeof(pre_update_res) == TYPE_BOOL and pre_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_UPDATE)
		return GPMUtils.OK()

	var dir := Directory.new()
	
	emit_signal("operation_started", "update", package_file[PackageKeys.PACKAGES].size())
	
	# Used for compiling together all errors that may occur
	var failed_packages := GPMFailedPackages.new()
	
	emit_signal("message_logged", "Building list of packages to update")
	var update_packages := list_packages_to_update(package_file, failed_packages)
	emit_signal("message_logged", "List of packages to update created")
	GPMUtils.mk(ADDONS_DIR_CACHE)
	for package_name in update_packages:
		emit_signal("operation_checkpoint_reached", package_name)
		
		var download_location: String
		var download_link: String

		var data: Dictionary = update_packages[package_name]

		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()
		var cache_dir: String = ADDONS_DIR_FORMAT_CACHE % package_name.get_file()

		var version = data["version"]
		var integrity = ""

		#------------
		#That's to get link to tarball! Only for NPM
		var should_skip = false

		match data["src"]:
			"git":
				emit_signal("message_logged", "Working with tar")
				download_location = ADDONS_DIR_FORMAT_CACHE.replace("res://", "./") % package_name
				download_link = data["url"]
			"tar": 
				emit_signal("message_logged", "Working with github")
				download_location = ADDONS_DIR_FORMAT_CACHE % (package_name+data["filename"])
				download_link = data["dist"]
			"npm":
				var npm_manifest: Dictionary
				emit_signal("message_logged", "Working with npm")

				res = yield(GPMNpm.request_npm_manifest(package_name, data["version"]), "completed")

				if not res or res.is_err():
					failed_packages.add_response(package_name, res)
					should_skip = true
				else:
					emit_signal("message_logged", "Downloaded npm manifest")
					npm_manifest = res.unwrap()
					
					download_link = npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL]

					download_location = ADDONS_DIR_FORMAT_CACHE % download_link.get_file()
					
					version = npm_manifest.get(NpmManifestKeys.VERSION, "__MISSING__")
					integrity = npm_manifest.get(NpmManifestKeys.DIST, {}).get(NpmManifestKeys.INTEGRITY, "__MISSING__")
		
		if should_skip:
			emit_signal("message_logged", "Skipping %s" % package_name)
			continue

		#------------
		# Check against lockfile and determine whether to continue or not
		# If the directory does not exist, there's no need to do addtional checks
		if dir.dir_exists(dir_name):
			if not force:
				if not _is_valid_new_package(lock_file, package_name, version, integrity):
					emit_signal("message_logged", "%s does not need to be updated\nSkipping %s" % [package_name, package_name])
					continue

			if GPMFs.remove_dir_recursive(ProjectSettings.globalize_path(dir_name)) != OK:
				emit_signal("message_logged", "Can't delete folder Skipping %s" % package_name)
				failed_packages.add_response(package_name, res)
				continue
	
		
		# Creating cache to store the result
		if not dir.dir_exists(ADDONS_DIR_CACHE):
			dir.make_dir_recursive(ADDONS_DIR_CACHE)

		res = null

		if data["src"] in ["tar", "npm"]:
			emit_signal("message_logged", "Downloading through wget %s" % package_name)
			res = GPMUtils.wget(download_link, download_location)

			if not res or res.is_err():
				failed_packages.add_response(package_name, res)
				continue
			
			emit_signal("message_logged", " Creating cache directory for %s" % package_name)
			if not dir.dir_exists(cache_dir):
				if dir.make_dir_recursive(cache_dir) != OK:
					failed_packages.add_response(package_name, "Can't create cache dir")
					continue

			emit_signal("message_logged", " Unzipping %s" % package_name)
			res = GPMUtils.xzf(download_location, cache_dir)
			if not res or res.is_err():
				failed_packages.add_response(package_name, res)
				continue
		elif data["src"] in ["git"]:
			emit_signal("message_logged", " Cloning %s" % package_name)
			res = GPMUtils.clone(download_link, download_location)			
			if not res or res.is_err():
				failed_packages.add_response(package_name, res)
				continue
		
		
		
		
		var src = cache_dir 

		if data.has("subdir"):
			src = src + "/" + data["subdir"]
		else:
			# Creating directory to store the result
			if not dir.dir_exists(dir_name):
				if dir.make_dir_recursive(dir_name) != OK:
					emit_signal("message_logged", "Can't create folder Skipping %s" % package_name)
					failed_packages.add(package_name, "Unable to create directory")
					continue
		
		GPMUtils.mv(src, "res://addons")
		#endregion
		
		# Saving lockfile
		lock_file[package_name] = {
			LockFileKeys.VERSION: data["version"],
			LockFileKeys.INTEGRITY: integrity,
			"path": src
		}
		res = write_config(LOCK_FILE, lock_file)
		if not res or res.is_err():
			failed_packages.add(package_name, "Unable to write configs")
	
# # Removing cache
	GPMUtils.rm(ADDONS_DIR_CACHE)

	emit_signal("operation_finished")
	
	var post_update_res = hooks.run(self, ValidHooks.POST_UPDATE)
	if typeof(post_update_res) == TYPE_BOOL and post_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_UPDATE)
		return GPMUtils.OK()
	
	if failed_packages.has_logs():
		return GPMUtils.ERR(GPMError.Code.PROCESS_PACKAGES_FAILURE, failed_packages.get_logs())


	return GPMUtils.OK()

## Remove all packages listed in `godot.lock`
##
## @return: GPMResult<()> - The result of the operation
func purge() -> GPMResult:
	var res := _read_all_configs()
	if not res:
		return GPMUtils.ERR(GPMError.Code.GENERIC, "Unable to read configs, bailing out")
	if res.is_err():
		return res

	var configs: Array = res.unwrap()

	var package_file: Dictionary = configs[0]
	var lock_file: Dictionary = configs[1]

	res = _parse_hooks(package_file)
	if res.is_err():
		return res

	var hooks: GPMHooks = res.unwrap()
	var pre_purge_res = hooks.run(self, ValidHooks.PRE_PURGE)
	if typeof(pre_purge_res) == TYPE_BOOL and pre_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_PURGE)
		return GPMUtils.OK()

	var dir := Directory.new()

	emit_signal("operation_started", "purge", lock_file.size())

	var failed_packages := GPMFailedPackages.new()
	var completed_package_count: int = 0
	for package_name in lock_file.keys():
		emit_signal("operation_checkpoint_reached", package_name)
		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()

		if dir.dir_exists(dir_name):
			if GPMFs.remove_dir_recursive(ProjectSettings.globalize_path(dir_name)) != OK:
				failed_packages.add(package_name, "Unable to remove directory")
				continue
	
	emit_signal("operation_finished")

	var post_purge_res = hooks.run(self, ValidHooks.POST_PURGE)
	if typeof(post_purge_res) == TYPE_BOOL and post_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_PURGE)
		return GPMUtils.OK()
	
	var keys_to_erase := []
	for key in lock_file.keys():
		if not key in failed_packages.failed_packages:
			keys_to_erase.append(key)
	
	for key in keys_to_erase:
		lock_file.erase(key)
	
	res = write_config(LOCK_FILE, lock_file)
	if res.is_err():
		return res

	return GPMUtils.OK() if not failed_packages.has_logs() else \
		GPMUtils.ERR(GPMError.Code.REMOVE_PACKAGE_DIR_FAILURE, failed_packages.get_logs())


#-----------------------------------

func print(text: String) -> void:
	print(text)
	emit_signal("message_logged", text)
