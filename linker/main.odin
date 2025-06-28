package main

import os "core:os/os2"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:path/filepath"

link_name :: "home"
link_prefix :: link_name + "-"
link_suffix :: "-link"

Entry :: struct {
	target: string,
	on_change: string
}

// Link path -> entry
// Format: link path<tab>target path<tab>onChange script path
Manifest :: map[string]Entry

log :: #force_inline proc(message: any) {
	fmt.eprintln(message)
}

logf :: #force_inline proc(format: string, args: ..any) {
	fmt.eprintfln(format, ..args)
}

read_manifest :: proc(path: string) -> (manifest: Manifest, ok: bool) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		logf("Failed to read %s: %s", path, os.error_string(err))
		return nil, false
	}
	defer delete(data)

	manifest = make(Manifest)
	defer if !ok do delete(manifest)

	data_string := string(data)
	for line in strings.split_lines_iterator(&data_string) {
		parts := strings.split_n(line, "\t", 3)
		defer delete(parts)
		if len(parts) < 3 {
			logf("Invalid manifest entry: %s", line)
			return nil, false
		}

		link := strings.clone(parts[0])
		manifest[link] = {
			target = strings.clone(parts[1]),
			on_change = strings.clone(parts[2])
		}
	}

	ok = true
	return
}

parse_generation :: proc(name: string) -> (uint, bool) {
	number := name[len(link_prefix):len(name) - len(link_suffix)]
	return strconv.parse_uint(number)
}

run :: proc() -> (code: int) {
	partial_activation :: "this will likely result in a partial activation. Fix the cause and reactivate."

	if len(os.args) < 3 {
		log("Usage: linker <profiles directory> <new manifest store path>")
		return 1
	}

	path_generations := os.args[1]
	path_new := filepath.clean(os.args[2])
	
	ok: bool
	err: os.Error

	number_current: uint = 0
 	manifest_current: Manifest
	exists_current := false

	path_link := filepath.join({path_generations, link_name})
	path_current: string
	path_current, err = os.read_link(path_link, context.allocator)
	if err == nil {
		name_current := filepath.base(path_current)
		number_current, ok = parse_generation(name_current)
		if !ok {
			logf("Current generation points to invalid name: %s -> %s", path_link, name_current)
			return 1
		}

		path_current, err = os.read_link(path_current, context.allocator)
		if err != nil {
			logf("Failed to readlink current manifest: %s", os.error_string(err))
			return 1
		}

		manifest_current, ok = read_manifest(path_current)
		if !ok {
			log("Failed to read current manifest")
			return 1
		}

		exists_current = true
	} else if err != os.General_Error.Not_Exist {
		logf("Failed to readlink current manifest: %s", os.error_string(err))
		return 1
	}

	defer if exists_current do delete(manifest_current)

	manifest_new: Manifest
	manifest_new, ok = read_manifest(path_new)
	if !ok {
		log("Failed to read new manifest")
		return 1
	}
	defer delete(manifest_new)

	for link, entry in manifest_new {
		if entry.target == "" do continue

		info, err := os.stat_do_not_follow_links(link, context.allocator)
		if err == nil {
			if info.type == os.File_Type.Symlink {
				err = os.remove(link)
				if err != nil {
					logf("Failed to remove link %s: %s, " + partial_activation, link, os.error_string(err))
					code = 1
					continue
				}
			} else {
				logf("%s exists but is not a link, skipping - " + partial_activation, link)
				code = 1
				continue
			}
		} else if err != os.General_Error.Not_Exist {
			logf("Failed to stat %s: %s, attempting to link anyway", link, os.error_string(err))
		}

		directory := filepath.dir(link)
		err = os.mkdir_all(directory)
		if err != nil && err != os.General_Error.Exist {
			logf("Failed to create parent directories for link (%s): %s, " + partial_activation)
			code = 1
			continue
		}

		err = os.symlink(entry.target, link)
		if err != nil {
			logf("Symlink failed (%s -> %s): %s, " + partial_activation, link, entry.target, os.error_string(err))
			code = 1
			continue
		}

		if entry.on_change != "" && exists_current {
			entry_current: Entry
			entry_current, ok = manifest_current[link]
			if ok && entry.target != entry_current.target {
				logf("Running onChange script (%s) for %s", entry.on_change, link)

				process, err := os.process_start({
					command = {entry.on_change},
					stdout = os.stdout,
					stderr = os.stderr
				})
				if err == nil {
					_, err = os.process_wait(process)
					if err != nil {
						logf("Failed to run onChange script for %s: %s", link, os.error_string(err))
						code = 1
					}
				} else {
					logf("Failed to start onChange script for %s: %s", link, os.error_string(err))
					code = 1
				}
			}
		}

		logf("%s -> %s", link, entry.target)
	}

	if path_new == path_current {
		return code;
	}

	if exists_current {
		for link in manifest_current {
			if link not_in manifest_new {
				err := os.remove(link)
				if err != nil && err != os.General_Error.Not_Exist {
					logf("Failed to remove dangling file (%s): %s", link, os.error_string(err))
					code = 1
					continue
				}

				logf("Removed %s", link)
			}
		}

		err := os.remove(path_link)
		if err != nil {
			logf("Failed to remove current generation link (%s): %s, " + partial_activation, path_link, os.error_string(err))
			return 1
		}
	} else {
		log("Warning: no current manifest, skipping cleanup")
		
		err = os.mkdir_all(path_generations)
		if err != nil && err != os.General_Error.Exist {
			logf("Failed to create parent directories (%s) for generation: %s", path_generations, os.error_string(err))
			return 1
		}
	}

	filename_new := fmt.tprintf(link_prefix + "%d" + link_suffix, number_current + 1)
	path_link_new := filepath.join({path_generations, filename_new})
	err = os.symlink(path_new, path_link_new)
	if err != nil {
		logf("Failed to symlink new generation (%s -> %s): %s", path_link_new, path_new, os.error_string(err))
		return 1
	}
	
	err = os.symlink(path_link_new, path_link)
	if err != nil {
		logf("Failed to symlink current generation (%s -> %s): %s", path_link, path_link_new, os.error_string(err))
		return 1
	}

	return
}

main :: proc() {
	os.exit(run())
}
