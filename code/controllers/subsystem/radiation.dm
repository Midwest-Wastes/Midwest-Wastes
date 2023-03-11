/// Makes irradiated areas flash green and have a number
/// if it does both, everything is fine. if not, then hecc
GLOBAL_VAR_INIT(rad_puddle_debug, FALSE)
PROCESSING_SUBSYSTEM_DEF(radiation)
	name = "Radiation"
	flags = SS_BACKGROUND|SS_POST_FIRE_TIMING|SS_NO_INIT

	var/list/warned_atoms = list()
	/// Contains a list of coordinates to turfs that are irradiated
	/// list("x:y:z" = rad_level)
	var/list/irradiated_turfs = list()
	/// irradiated mobs, to be blasted with radiation every tick
	/// list("mob_whatever" = rad_level)
	var/list/irradiated_mobs = list()
	/// A list of \refs to check periodically
	var/list/irradiators = list()
	/// Occasionally clean up the irradiated mobs and turfs
	COOLDOWN_DECLARE(cleanup_radiation)
	/// debug command, dont use
	var/greened = FALSE

/datum/controller/subsystem/processing/radiation/fire(resumed)
	tick_radpuddles()
	. = ..()

/datum/controller/subsystem/processing/radiation/proc/tick_radpuddles(resumed)
	if(COOLDOWN_FINISHED(src, cleanup_radiation))
		cleanup_radiation()
		COOLDOWN_START(src, cleanup_radiation, 15 MINUTES)
	for(var/glowie in irradiated_mobs)
		var/mob/living/carbon/human/glowman = locate(glowie)
		if(!istype(glowman))
			irradiated_mobs -= glowie
			continue
		var/coordz = "[glowman.x]:[glowman.y]:[glowman.z]"
		if(!irradiated_turfs[coordz])
			irradiated_turfs -= coordz
			irradiated_mobs -= glowie
			continue
		var/turf/check_turf = locate(glowman.x, glowman.y, glowman.z)
		if(!SEND_SIGNAL(check_turf, COMSIG_TURF_RADIOACTIVE)) // is that turf radioactive? if not, then, wierd
			irradiated_turfs -= coordz
			irradiated_mobs -= glowie
			continue
		glowman.rad_act(irradiated_turfs[coordz])
	if(GLOB.rad_puddle_debug)
		for(var/coordie in irradiated_turfs)
			var/turf/helpme = coords2turf(coordie)
			if(helpme)
				helpme.color = greened ? initial(helpme.color) : "#00ff00"
		greened = !greened

/// Periodically checks all the turf coordinates are both there and supposed to be radioactive
/datum/controller/subsystem/processing/radiation/proc/cleanup_radiation()
	for(var/turfie in irradiated_turfs)
		var/turf/fieturf = coords2turf(turfie)
		if(!fieturf)
			irradiated_turfs -= turfie
			continue
		if(QDELETED(fieturf))
			irradiated_turfs -= turfie
			continue
		if(!SEND_SIGNAL(fieturf, COMSIG_TURF_RADIOACTIVE))
			irradiated_turfs -= turfie
			continue

/// the irradiated tile got changed and its component deleted, check back in a split second and apply a new one there
/datum/controller/subsystem/processing/radiation/proc/tile_got_changed(turf_coords, list/puddles, new_rads)
	addtimer(CALLBACK(src, .proc/add_radtile, turf_coords, puddles, new_rads, 5), 2, TIMER_UNIQUE|TIMER_OVERRIDE) //*pain //*doublepain

/datum/controller/subsystem/processing/radiation/proc/add_radtile(turf_coords, list/puddles, new_rads, tries = 5)
	if(new_rads <= 0) // if it isnt radioactive, then, fuck
		irradiated_turfs -= turf_coords
		return
	var/turf/new_turf = coords2turf(turf_coords)
	/// the new turf either doesnt exist, or is still being replaced, check back in another split second
	if(!new_turf || QDELETED(new_turf))
		if(tries)
			addtimer(CALLBACK(src, .proc/add_radtile, turf_coords, puddles, new_rads, tries - 1), 2, TIMER_UNIQUE|TIMER_OVERRIDE) //*pain //*doublepain
		irradiated_turfs -= turf_coords
		return // okay fine, there's a hole to nothing right here, fucking, cool.
	/// turf found, check if the puddles still exist
	var/good_puddles = list()
	for(var/reffie in puddles)
		var/obj/effect/decal/waste/plip = RESOLVEREF(reffie)
		if(plip && !QDELETED(plip))
			good_puddles |= reffie
	if(!LAZYLEN(good_puddles))
		irradiated_turfs -= turf_coords
		return // puddles are missing, likely, so unirradiate this turf
	// okay, turf exists, has puddles somewhere, and is in fact radioactive. know what this means?
	if(SEND_SIGNAL(new_turf, COMSIG_TURF_RADIOACTIVE)) // okay check if there's still a component there first
		return // and let it be
	// okay NOW shove a component in there
	new_turf.AddComponent(/datum/component/radiation_turf, new_rads, good_puddles)

/datum/controller/subsystem/processing/radiation/proc/warn(datum/component/radioactive/contamination)
	if(!contamination || QDELETED(contamination))
		return
	var/ref = REF(contamination.parent)
	if(warned_atoms[ref])
		return
	warned_atoms[ref] = TRUE
	var/atom/master = contamination.parent
	SSblackbox.record_feedback("tally", "contaminated", 1, master.type)
	var/msg = "has become contamintaed with enough radiation to contaminate other objects. || Source: [contamination.source] || Strength: [contamination.strength]"
	master.investigate_log(msg, INVESTIGATE_RADIATION)
